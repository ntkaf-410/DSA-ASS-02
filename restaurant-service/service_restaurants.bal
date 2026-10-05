import ballerina/http;
import ballerina/log;
import ballerina/sql;

// REST API of the Restaurant Service. Base path /restaurants, port 8082.

listener http:Listener httpListener = new (servicePort);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /restaurants on httpListener {

    // restaurants

    resource function post .(@http:Payload RestaurantInput payload)
            returns http:Created|http:BadRequest|http:Conflict|http:InternalServerError {
        string? invalid = validateRestaurant(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        int|error newId = insertRestaurant(payload);
        if newId is error {
            if isDuplicateKey(newId) {
                return conflictResponse("A restaurant with this name and address already exists");
            }
            log:printError("Restaurant insert failed", newId);
            return internalError();
        }
        Restaurant|sql:Error created = getRestaurant(newId);
        if created is sql:Error {
            log:printError("Could not load created restaurant", created, restaurantId = newId);
            return internalError();
        }
        return <http:Created>{
            headers: {"Location": string `/restaurants/${newId}`},
            body: created
        };
    }

    # Active restaurants only. Optional ?city= and ?cuisine= filters.
    resource function get .(string? city, string? cuisine, int page = 1, int pageSize = 20)
            returns Restaurant[]|http:BadRequest|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        Restaurant[]|error list = listRestaurants(city, cuisine, pageSize, (page - 1) * pageSize);
        if list is error {
            log:printError("Listing restaurants failed", list);
            return internalError();
        }
        return list;
    }

    resource function get [int id]() returns Restaurant|http:NotFound|http:InternalServerError {
        Restaurant|sql:Error r = getRestaurant(id);
        if r is Restaurant {
            return r;
        }
        if r is sql:NoRowsError {
            return notFound(string `Restaurant ${id} not found`);
        }
        log:printError("Restaurant lookup failed", r, restaurantId = id);
        return internalError();
    }

    resource function put [int id](@http:Payload RestaurantInput payload)
            returns Restaurant|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        string? invalid = validateRestaurant(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        error? updated = updateRestaurant(id, payload);
        if updated is error {
            if isDuplicateKey(updated) {
                return conflictResponse("A restaurant with this name and address already exists");
            }
            log:printError("Restaurant update failed", updated, restaurantId = id);
            return internalError();
        }
        Restaurant|sql:Error r = getRestaurant(id);
        if r is Restaurant {
            return r;
        }
        if r is sql:NoRowsError {
            return notFound(string `Restaurant ${id} not found`);
        }
        return internalError();
    }

    resource function delete [int id]() returns http:NoContent|http:NotFound|http:InternalServerError {
        int|error rows = deleteRestaurant(id);
        if rows is error {
            log:printError("Restaurant delete failed", rows, restaurantId = id);
            return internalError();
        }
        if rows == 0 {
            return notFound(string `Restaurant ${id} not found`);
        }
        return http:NO_CONTENT;
    }

    // Quick check the Order Service can call before it creates an order.
    resource function get [int id]/status()
            returns RestaurantStatus|http:NotFound|http:InternalServerError {
        Restaurant|sql:Error r = getRestaurant(id);
        if r is sql:NoRowsError {
            return notFound(string `Restaurant ${id} not found`);
        }
        if r is sql:Error {
            log:printError("Restaurant lookup failed", r, restaurantId = id);
            return internalError();
        }
        OpeningHours[]|error hours = listOpeningHours(id);
        if hours is error {
            log:printError("Loading opening hours failed", hours, restaurantId = id);
            return internalError();
        }
        boolean open = isOpenNow(hours);
        return {
            restaurantId: id,
            isActive: r.isActive,
            isOpen: open,
            acceptingOrders: r.isActive && open
        };
    }

    // opening hours

    // Replaces the whole weekly schedule.
    resource function put [int id]/hours(@http:Payload OpeningHoursInput[] payload)
            returns OpeningHours[]|http:BadRequest|http:NotFound|http:InternalServerError {
        http:NotFound|http:InternalServerError? guard = ensureRestaurant(id);
        if guard !is () {
            return guard;
        }
        string? invalid = validateHours(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        error? saved = replaceOpeningHours(id, payload);
        if saved is error {
            log:printError("Saving opening hours failed", saved, restaurantId = id);
            return internalError();
        }
        OpeningHours[]|error hours = listOpeningHours(id);
        if hours is error {
            return internalError();
        }
        return hours;
    }

    resource function get [int id]/hours()
            returns OpeningHours[]|http:NotFound|http:InternalServerError {
        http:NotFound|http:InternalServerError? guard = ensureRestaurant(id);
        if guard !is () {
            return guard;
        }
        OpeningHours[]|error hours = listOpeningHours(id);
        if hours is error {
            log:printError("Listing opening hours failed", hours, restaurantId = id);
            return internalError();
        }
        return hours;
    }

    // menu and inventory

    resource function post [int id]/menu(@http:Payload MenuItemInput payload)
            returns http:Created|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        http:NotFound|http:InternalServerError? guard = ensureRestaurant(id);
        if guard !is () {
            return guard;
        }
        string? invalid = validateMenuItem(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        int|error itemId = insertMenuItem(id, payload);
        if itemId is error {
            if isDuplicateKey(itemId) {
                return conflictResponse("This restaurant already has a menu item with that name");
            }
            log:printError("Menu item insert failed", itemId, restaurantId = id);
            return internalError();
        }
        MenuItem|sql:Error item = getMenuItem(id, itemId);
        if item is sql:Error {
            return internalError();
        }
        return <http:Created>{
            headers: {"Location": string `/restaurants/${id}/menu/${itemId}`},
            body: item
        };
    }

    // ?category= filters by category, ?available=true hides switched-off and sold-out items.
    resource function get [int id]/menu(string? category, boolean available = false)
            returns MenuItem[]|http:NotFound|http:InternalServerError {
        http:NotFound|http:InternalServerError? guard = ensureRestaurant(id);
        if guard !is () {
            return guard;
        }
        MenuItem[]|error items = listMenu(id, category, available);
        if items is error {
            log:printError("Listing menu failed", items, restaurantId = id);
            return internalError();
        }
        return items;
    }

    resource function get [int id]/menu/[int itemId]()
            returns MenuItem|http:NotFound|http:InternalServerError {
        MenuItem|sql:Error item = getMenuItem(id, itemId);
        if item is MenuItem {
            return item;
        }
        if item is sql:NoRowsError {
            return notFound(string `Menu item ${itemId} not found for restaurant ${id}`);
        }
        log:printError("Menu item lookup failed", item);
        return internalError();
    }

    resource function put [int id]/menu/[int itemId](@http:Payload MenuItemInput payload)
            returns MenuItem|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        string? invalid = validateMenuItem(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        error? updated = updateMenuItem(id, itemId, payload);
        if updated is error {
            if isDuplicateKey(updated) {
                return conflictResponse("This restaurant already has a menu item with that name");
            }
            log:printError("Menu item update failed", updated);
            return internalError();
        }
        MenuItem|sql:Error item = getMenuItem(id, itemId);
        if item is MenuItem {
            return item;
        }
        if item is sql:NoRowsError {
            return notFound(string `Menu item ${itemId} not found for restaurant ${id}`);
        }
        return internalError();
    }

    // Sets the stock to an exact number (e.g. after a delivery of ingredients).
    resource function put [int id]/menu/[int itemId]/stock(@http:Payload StockUpdate payload)
            returns MenuItem|http:BadRequest|http:NotFound|http:InternalServerError {
        if payload.stockQuantity < 0 {
            return badRequest("stockQuantity cannot be negative");
        }
        error? updated = setStock(id, itemId, payload.stockQuantity);
        if updated is error {
            log:printError("Stock update failed", updated);
            return internalError();
        }
        MenuItem|sql:Error item = getMenuItem(id, itemId);
        if item is MenuItem {
            return item;
        }
        if item is sql:NoRowsError {
            return notFound(string `Menu item ${itemId} not found for restaurant ${id}`);
        }
        return internalError();
    }

    resource function delete [int id]/menu/[int itemId]()
            returns http:NoContent|http:NotFound|http:InternalServerError {
        int|error rows = deleteMenuItem(id, itemId);
        if rows is error {
            log:printError("Menu item delete failed", rows);
            return internalError();
        }
        if rows == 0 {
            return notFound(string `Menu item ${itemId} not found for restaurant ${id}`);
        }
        return http:NO_CONTENT;
    }

    // kitchen orders

    // Orders that reached this restaurant, newest first. Optional ?status=
    resource function get [int id]/orders(string? status, int page = 1, int pageSize = 20)
            returns KitchenOrder[]|http:BadRequest|http:NotFound|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        http:NotFound|http:InternalServerError? guard = ensureRestaurant(id);
        if guard !is () {
            return guard;
        }
        string? statusFilter = status is string ? status.toUpperAscii() : ();
        KitchenOrder[]|error orders = listKitchenOrders(id, statusFilter, pageSize, (page - 1) * pageSize);
        if orders is error {
            log:printError("Listing kitchen orders failed", orders, restaurantId = id);
            return internalError();
        }
        return orders;
    }

    resource function get [int id]/orders/[string orderId]()
            returns KitchenOrder|http:NotFound|http:InternalServerError {
        KitchenOrder|error o = getKitchenOrder(id, orderId);
        if o is KitchenOrder {
            return o;
        }
        if o is sql:NoRowsError {
            return notFound(string `Order ${orderId} not found for restaurant ${id}`);
        }
        log:printError("Kitchen order lookup failed", o);
        return internalError();
    }

    // Kitchen moves an order forward: CONFIRMED -> PREPARING -> READY.
    // Publishes the change so the Order Service can update its state machine.
    resource function put [int id]/orders/[string orderId]/status(@http:Payload StatusUpdate payload)
            returns KitchenOrder|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        string target = payload.status.trim().toUpperAscii();
        if target != "PREPARING" && target != "READY" {
            return badRequest("status must be PREPARING or READY");
        }
        KitchenOrder|error current = getKitchenOrder(id, orderId);
        if current is sql:NoRowsError {
            return notFound(string `Order ${orderId} not found for restaurant ${id}`);
        }
        if current is error {
            log:printError("Kitchen order lookup failed", current);
            return internalError();
        }
        if NEXT_STATUS[current.status] != target {
            return conflictResponse(string `Order is ${current.status}, it cannot go to ${target}`);
        }
        int|error rows = advanceOrder(id, orderId, current.status, target);
        if rows is error {
            log:printError("Order status update failed", rows, orderId = orderId);
            return internalError();
        }
        if rows == 0 {
            return conflictResponse("Order status changed in the meantime, please reload");
        }
        publishOrderStatus(orderId, id, target);
        KitchenOrder|error updated = getKitchenOrder(id, orderId);
        if updated is KitchenOrder {
            return updated;
        }
        return internalError();
    }
}

// Liveness probe used by the Docker healthcheck.
service /health on httpListener {
    resource function get .() returns json|http:ServiceUnavailable {
        int|error ping = dbClient->queryRow(`SELECT 1`);
        if ping is error {
            return <http:ServiceUnavailable>{body: {"status": "DOWN", "service": "restaurant-service"}};
        }
        return {"status": "UP", "service": "restaurant-service"};
    }
}

// () when the restaurant exists, otherwise a ready-made error response.
function ensureRestaurant(int id) returns http:NotFound|http:InternalServerError? {
    boolean|error exists = restaurantExists(id);
    if exists is error {
        log:printError("Restaurant existence check failed", exists, restaurantId = id);
        return internalError();
    }
    if !exists {
        return notFound(string `Restaurant ${id} not found`);
    }
    return;
}
