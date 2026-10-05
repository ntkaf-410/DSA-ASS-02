import ballerina/http;
import ballerina/log;
import ballerina/uuid;

listener http:Listener httpListener = new (port);

function errResp(int status, string code, string message) returns http:Response {
    http:Response r = new;
    r.statusCode = status;
    r.setJsonPayload({code, message});
    return r;
}

function jsonResp(int status, json body) returns http:Response {
    http:Response r = new;
    r.statusCode = status;
    r.setJsonPayload(body);
    return r;
}

function mapError(error e) returns http:Response {
    if e is OrderNotFound {
        return errResp(404, "NOT_FOUND", e.message());
    }
    if e is InvalidTransition || e is ConflictError {
        return errResp(409, "INVALID_STATE", e.message());
    }
    log:printError("unexpected error", e);
    return errResp(500, "INTERNAL_ERROR", "unexpected error");
}

function validateCreate(CreateOrderRequest req) returns string? {
    if req.restaurantId <= 0 {
        return "restaurantId must be positive";
    }
    if req.items.length() == 0 {
        return "at least one item is required";
    }
    foreach CreateOrderItem it in req.items {
        if it.quantity <= 0 {
            return string `quantity for item ${it.menuItemId} must be positive`;
        }
    }
    return ();
}

service /orders on httpListener {

    // Create an order: validate -> price from the live menu -> persist (CREATED) -> publish orders.created
    resource function post .(@http:Payload CreateOrderRequest req) returns http:Response {
        string? problem = validateCreate(req);
        if problem is string {
            return errResp(400, "BAD_REQUEST", problem);
        }

        boolean|error addrOk = addressExists(req.customerId, req.deliveryAddressId);
        if addrOk is error {
            log:printError("customer-service lookup failed", addrOk);
            return errResp(503, "UPSTREAM_UNAVAILABLE", "customer-service is unavailable");
        }
        if !addrOk {
            return errResp(404, "ADDRESS_NOT_FOUND", "customer or delivery address does not exist");
        }

        string|error rs = checkRestaurant(req.restaurantId);
        if rs is error {
            log:printError("restaurant-service lookup failed", rs);
            return errResp(503, "UPSTREAM_UNAVAILABLE", "restaurant-service is unavailable");
        }
        if rs == "NOT_FOUND" {
            return errResp(404, "RESTAURANT_NOT_FOUND", "restaurant does not exist");
        }
        if rs == "NOT_ACCEPTING" {
            return errResp(409, "RESTAURANT_NOT_ACCEPTING", "restaurant is closed or not accepting orders");
        }

        MenuItemView[]|error menu = fetchMenu(req.restaurantId);
        if menu is error {
            log:printError("menu lookup failed", menu);
            return errResp(503, "UPSTREAM_UNAVAILABLE", "restaurant-service is unavailable");
        }
        map<MenuItemView> byId = {};
        foreach MenuItemView m in menu {
            byId[m.id.toString()] = m;
        }

        // Prices and names come from the menu, never from the client.
        OrderItem[] items = [];
        decimal total = 0d;
        foreach CreateOrderItem ci in req.items {
            MenuItemView? m = byId[ci.menuItemId.toString()];
            if m is () {
                return errResp(400, "UNKNOWN_ITEM", string `item ${ci.menuItemId} is not on this restaurant's menu`);
            }
            if !m.isAvailable {
                return errResp(409, "ITEM_UNAVAILABLE", string `${m.name} is not available`);
            }
            items.push({menuItemId: m.id, name: m.name, quantity: ci.quantity, unitPrice: m.price});
            total += <decimal>ci.quantity * m.price;
        }

        OrderRecord o = {
            orderId: uuid:createType4AsString(),
            customerId: req.customerId,
            restaurantId: req.restaurantId,
            deliveryAddressId: req.deliveryAddressId,
            totalAmount: total,
            status: CREATED,
            paymentStatus: "PENDING",
            items: items,
            createdAt: "",
            updatedAt: ""
        };
        error? ins = insertOrder(o);
        if ins is error {
            log:printError("insert order failed", ins);
            return errResp(500, "INTERNAL_ERROR", "could not save order");
        }
        publishOrderCreated(o);

        OrderRecord?|error saved = getOrder(o.orderId);
        OrderRecord result = saved is OrderRecord ? saved : o;
        http:Response r = jsonResp(201, result.toJson());
        r.setHeader("Location", string `/orders/${o.orderId}`);
        return r;
    }

    resource function get .(int? customerId, string? status, int page = 1, int pageSize = 20)
            returns http:Response {
        if page < 1 || pageSize < 1 || pageSize > 100 {
            return errResp(400, "BAD_REQUEST", "page >= 1 and 1 <= pageSize <= 100");
        }
        if status is string && !isValidStatus(status) {
            return errResp(400, "BAD_REQUEST", "unknown status " + status);
        }
        OrderRecord[]|error res = listOrders(customerId, status, page, pageSize);
        if res is error {
            return mapError(res);
        }
        return jsonResp(200, res.toJson());
    }

    resource function get [string orderId]() returns http:Response {
        OrderRecord?|error res = getOrder(orderId);
        if res is error {
            return mapError(res);
        }
        if res is () {
            return errResp(404, "NOT_FOUND", string `order ${orderId} not found`);
        }
        return jsonResp(200, res.toJson());
    }

    resource function get [string orderId]/history() returns http:Response {
        OrderRecord?|error res = getOrder(orderId);
        if res is error {
            return mapError(res);
        }
        if res is () {
            return errResp(404, "NOT_FOUND", string `order ${orderId} not found`);
        }
        StatusHistoryEntry[]|error h = getHistory(orderId);
        if h is error {
            return mapError(h);
        }
        return jsonResp(200, h.toJson());
    }

    // Manual/fallback override. Normally Restaurant Service drives these via restaurants.order.status (Kafka).
    resource function put [string orderId]/status(@http:Payload StatusUpdateRequest req)
            returns http:Response {
        if req.status != PREPARING && req.status != READY && req.status != CANCELLED {
            return errResp(400, "BAD_REQUEST", "REST may only set PREPARING, READY or CANCELLED");
        }
        OrderRecord|error res = applyTransition(orderId, req.status, "restaurant-api");
        if res is error {
            return mapError(res);
        }
        return jsonResp(200, res.toJson());
    }

    resource function post [string orderId]/cancel() returns http:Response {
        OrderRecord|error res = applyTransition(orderId, CANCELLED, "customer-api");
        if res is error {
            return mapError(res);
        }
        return jsonResp(200, res.toJson());
    }
}

service /health on httpListener {
    resource function get .() returns http:Response {
        error? e = pingDb();
        if e is error {
            return errResp(503, "UNHEALTHY", "database unreachable");
        }
        return jsonResp(200, {status: "UP", name: "order-service"});
    }
}
