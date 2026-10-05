import ballerina/lang.value;
import ballerina/sql;

// Every SQL statement lives here, all parameterised. Handlers and Kafka code never build SQL.

// restaurants

function restaurantSelect() returns sql:ParameterizedQuery =>
    `SELECT id, name, description, cuisine, phone, address, city, latitude, longitude,
            is_active AS isActive,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
     FROM restaurants`;

function insertRestaurant(RestaurantInput r) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(`
        INSERT INTO restaurants (name, description, cuisine, phone, address, city, latitude, longitude)
        VALUES (${r.name}, ${r.description}, ${r.cuisine}, ${r.phone}, ${r.address},
                ${r.city}, ${r.latitude}, ${r.longitude})`);
    string|int? id = res.lastInsertId;
    if id is int {
        return id;
    }
    return error("Could not read generated restaurant id");
}

function getRestaurant(int id) returns Restaurant|sql:Error {
    return dbClient->queryRow(sql:queryConcat(restaurantSelect(), ` WHERE id = ${id}`));
}

function listRestaurants(string? city, string? cuisine, int pageSize, int offset) returns Restaurant[]|error {
    sql:ParameterizedQuery q = sql:queryConcat(restaurantSelect(), ` WHERE is_active = TRUE`);
    if city is string {
        q = sql:queryConcat(q, ` AND city = ${city}`);
    }
    if cuisine is string {
        q = sql:queryConcat(q, ` AND cuisine = ${cuisine}`);
    }
    q = sql:queryConcat(q, ` ORDER BY name LIMIT ${pageSize} OFFSET ${offset}`);
    stream<Restaurant, sql:Error?> rs = dbClient->query(q);
    return from Restaurant r in rs
        select r;
}

function restaurantExists(int id) returns boolean|error {
    int n = check dbClient->queryRow(`SELECT COUNT(*) FROM restaurants WHERE id = ${id}`);
    return n > 0;
}

function updateRestaurant(int id, RestaurantInput r) returns error? {
    // COALESCE keeps the old value when isActive is left out of the request
    _ = check dbClient->execute(`
        UPDATE restaurants
        SET name = ${r.name}, description = ${r.description}, cuisine = ${r.cuisine},
            phone = ${r.phone}, address = ${r.address}, city = ${r.city},
            latitude = ${r.latitude}, longitude = ${r.longitude},
            is_active = COALESCE(${r.isActive}, is_active)
        WHERE id = ${id}`);
}

function deleteRestaurant(int id) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(`DELETE FROM restaurants WHERE id = ${id}`);
    return res.affectedRowCount ?: 0;
}

// opening hours

# Replaces the whole week in one transaction so a half-saved schedule can't exist.
function replaceOpeningHours(int restaurantId, OpeningHoursInput[] hours) returns error? {
    transaction {
        _ = check dbClient->execute(`DELETE FROM opening_hours WHERE restaurant_id = ${restaurantId}`);
        foreach OpeningHoursInput h in hours {
            boolean closed = h.isClosed ?: false;
            string? openAt = closed ? () : h.openTime;
            string? closeAt = closed ? () : h.closeTime;
            _ = check dbClient->execute(`
                INSERT INTO opening_hours (restaurant_id, day_of_week, open_time, close_time, is_closed)
                VALUES (${restaurantId}, ${h.dayOfWeek}, ${openAt}, ${closeAt}, ${closed})`);
        }
        check commit;
    }
}

function listOpeningHours(int restaurantId) returns OpeningHours[]|error {
    stream<OpeningHours, sql:Error?> rs = dbClient->query(`
        SELECT day_of_week AS dayOfWeek, is_closed AS isClosed,
               TIME_FORMAT(open_time, '%H:%i') AS openTime,
               TIME_FORMAT(close_time, '%H:%i') AS closeTime
        FROM opening_hours WHERE restaurant_id = ${restaurantId}
        ORDER BY day_of_week`);
    return from OpeningHours h in rs
        select h;
}

// menu + inventory

function menuSelect() returns sql:ParameterizedQuery =>
    `SELECT id, restaurant_id AS restaurantId, name, description, category, price,
            is_available AS isAvailable, stock_quantity AS stockQuantity,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
     FROM menu_items`;

function insertMenuItem(int restaurantId, MenuItemInput m) returns int|error {
    int stock = m.stockQuantity ?: 0;
    boolean available = m.isAvailable ?: true;
    sql:ExecutionResult res = check dbClient->execute(`
        INSERT INTO menu_items (restaurant_id, name, description, category, price, is_available, stock_quantity)
        VALUES (${restaurantId}, ${m.name}, ${m.description}, ${m.category}, ${m.price},
                ${available}, ${stock})`);
    string|int? id = res.lastInsertId;
    if id is int {
        return id;
    }
    return error("Could not read generated menu item id");
}

function getMenuItem(int restaurantId, int itemId) returns MenuItem|sql:Error {
    return dbClient->queryRow(sql:queryConcat(menuSelect(),
        ` WHERE id = ${itemId} AND restaurant_id = ${restaurantId}`));
}

# onlyAvailable hides items that are switched off or sold out.
function listMenu(int restaurantId, string? category, boolean onlyAvailable) returns MenuItem[]|error {
    sql:ParameterizedQuery q = sql:queryConcat(menuSelect(), ` WHERE restaurant_id = ${restaurantId}`);
    if category is string {
        q = sql:queryConcat(q, ` AND category = ${category}`);
    }
    if onlyAvailable {
        q = sql:queryConcat(q, ` AND is_available = TRUE AND stock_quantity > 0`);
    }
    q = sql:queryConcat(q, ` ORDER BY category, name`);
    stream<MenuItem, sql:Error?> rs = dbClient->query(q);
    return from MenuItem m in rs
        select m;
}

function updateMenuItem(int restaurantId, int itemId, MenuItemInput m) returns error? {
    // stock and availability keep their old values if the request leaves them out
    _ = check dbClient->execute(`
        UPDATE menu_items
        SET name = ${m.name}, description = ${m.description}, category = ${m.category},
            price = ${m.price},
            is_available = COALESCE(${m.isAvailable}, is_available),
            stock_quantity = COALESCE(${m.stockQuantity}, stock_quantity)
        WHERE id = ${itemId} AND restaurant_id = ${restaurantId}`);
}

function setStock(int restaurantId, int itemId, int quantity) returns error? {
    _ = check dbClient->execute(`
        UPDATE menu_items SET stock_quantity = ${quantity}
        WHERE id = ${itemId} AND restaurant_id = ${restaurantId}`);
}

function deleteMenuItem(int restaurantId, int itemId) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(
        `DELETE FROM menu_items WHERE id = ${itemId} AND restaurant_id = ${restaurantId}`);
    return res.affectedRowCount ?: 0;
}

// kitchen orders

function kitchenSelect() returns sql:ParameterizedQuery =>
    `SELECT order_id AS orderId, restaurant_id AS restaurantId, customer_id AS customerId,
            status, reject_reason AS rejectReason, items_json AS itemsJson,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt,
            DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%s') AS updatedAt
     FROM kitchen_orders`;

function toKitchenOrder(KitchenOrderRow r) returns KitchenOrder|error {
    json items = check value:fromJsonString(r.itemsJson ?: "[]");
    return {
        orderId: r.orderId,
        restaurantId: r.restaurantId,
        customerId: r.customerId,
        status: r.status,
        rejectReason: r.rejectReason,
        items,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt
    };
}

function kitchenOrderExists(string orderId) returns boolean|error {
    int n = check dbClient->queryRow(`SELECT COUNT(*) FROM kitchen_orders WHERE order_id = ${orderId}`);
    return n > 0;
}

function getKitchenOrder(int restaurantId, string orderId) returns KitchenOrder|error {
    KitchenOrderRow row = check dbClient->queryRow(sql:queryConcat(kitchenSelect(),
        ` WHERE order_id = ${orderId} AND restaurant_id = ${restaurantId}`));
    return toKitchenOrder(row);
}

function listKitchenOrders(int restaurantId, string? status, int pageSize, int offset)
        returns KitchenOrder[]|error {
    sql:ParameterizedQuery q = sql:queryConcat(kitchenSelect(), ` WHERE restaurant_id = ${restaurantId}`);
    if status is string {
        q = sql:queryConcat(q, ` AND status = ${status}`);
    }
    q = sql:queryConcat(q, ` ORDER BY created_at DESC LIMIT ${pageSize} OFFSET ${offset}`);
    stream<KitchenOrderRow, sql:Error?> rs = dbClient->query(q);
    KitchenOrder[] result = [];
    check from KitchenOrderRow row in rs
        do {
            result.push(check toKitchenOrder(row));
        };
    return result;
}

# Moves an order one step forward. The WHERE on the old status stops two clicks racing.
function advanceOrder(int restaurantId, string orderId, string fromStatus, string toStatus) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(`
        UPDATE kitchen_orders SET status = ${toStatus}
        WHERE order_id = ${orderId} AND restaurant_id = ${restaurantId} AND status = ${fromStatus}`);
    return res.affectedRowCount ?: 0;
}

# Takes the stock for every line and records the order as CONFIRMED, all or nothing.
# Returns () on success or the reason when something is out of stock.
function acceptOrder(OrderRequest req) returns string?|error {
    string? failure = ();
    transaction {
        json[] enriched = [];
        foreach OrderLine line in req.lines {
            // the stock check is inside the UPDATE, so two orders can't both grab the last portion
            sql:ExecutionResult res = check dbClient->execute(`
                UPDATE menu_items SET stock_quantity = stock_quantity - ${line.quantity}
                WHERE id = ${line.menuItemId} AND restaurant_id = ${req.restaurantId}
                  AND is_available = TRUE AND stock_quantity >= ${line.quantity}`);
            if (res.affectedRowCount ?: 0) == 0 {
                failure = string `Item ${line.menuItemId} is unavailable or out of stock`;
                break;
            }
            string itemName = check dbClient->queryRow(
                `SELECT name FROM menu_items WHERE id = ${line.menuItemId}`);
            _ = check dbClient->execute(`
                INSERT INTO stock_reservations (order_id, menu_item_id, quantity)
                VALUES (${req.orderId}, ${line.menuItemId}, ${line.quantity})`);
            enriched.push({menuItemId: line.menuItemId, name: itemName, quantity: line.quantity});
        }
        if failure is () {
            _ = check dbClient->execute(`
                INSERT INTO kitchen_orders (order_id, restaurant_id, customer_id, status, items_json)
                VALUES (${req.orderId}, ${req.restaurantId}, ${req.customerId}, 'CONFIRMED',
                        ${enriched.toJsonString()})`);
            check commit;
        } else {
            rollback;
        }
    }
    return failure;
}

function saveRejectedOrder(OrderRequest req, string reason) returns error? {
    // INSERT IGNORE: a duplicate delivery of the same event just does nothing
    _ = check dbClient->execute(`
        INSERT IGNORE INTO kitchen_orders (order_id, restaurant_id, customer_id, status, reject_reason, items_json)
        VALUES (${req.orderId}, ${req.restaurantId}, ${req.customerId}, 'REJECTED', ${reason},
                ${req.lines.toJsonString()})`);
}

# Gives the reserved stock back and marks the order CANCELLED.
# Returns false when there was nothing to cancel (unknown order, or already cancelled/rejected).
function cancelOrderAndRestock(string orderId) returns boolean|error {
    transaction {
        // FOR UPDATE locks the row so a double cancel can't restock twice
        string|sql:Error current = dbClient->queryRow(
            `SELECT status FROM kitchen_orders WHERE order_id = ${orderId} FOR UPDATE`);
        if current is sql:NoRowsError {
            rollback;
            return false;
        }
        string status = check current;
        if status == "CANCELLED" || status == "REJECTED" {
            rollback;
            return false;
        }
        _ = check dbClient->execute(`
            UPDATE menu_items m
            JOIN stock_reservations r ON r.menu_item_id = m.id
            SET m.stock_quantity = m.stock_quantity + r.quantity
            WHERE r.order_id = ${orderId}`);
        _ = check dbClient->execute(
            `UPDATE kitchen_orders SET status = 'CANCELLED' WHERE order_id = ${orderId}`);
        check commit;
    }
    return true;
}
