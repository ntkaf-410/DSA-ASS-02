import ballerina/sql;

// Every SQL statement lives here, all parameterised. Handlers and Kafka code never build SQL.

// drivers

function driverSelect() returns sql:ParameterizedQuery =>
    `SELECT id, full_name AS fullName, phone, vehicle, plate_number AS plateNumber, status,
            latitude, longitude,
            DATE_FORMAT(location_updated_at, '%Y-%m-%dT%H:%i:%sZ') AS locationUpdatedAt,
            DATE_FORMAT(last_assigned_at, '%Y-%m-%dT%H:%i:%sZ') AS lastAssignedAt,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS createdAt
     FROM drivers`;

function insertDriver(DriverInput d) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(`
        INSERT INTO drivers (full_name, phone, vehicle, plate_number)
        VALUES (${d.fullName.trim()}, ${d.phone.trim()}, ${d?.vehicle}, ${d?.plateNumber})`);
    string|int? id = res.lastInsertId;
    if id is int {
        return id;
    }
    return error("Could not read generated driver id");
}

function getDriver(int id) returns Driver|sql:Error {
    return dbClient->queryRow(sql:queryConcat(driverSelect(), ` WHERE id = ${id}`));
}

function listDrivers(string? status) returns Driver[]|error {
    sql:ParameterizedQuery q = driverSelect();
    if status is string {
        q = sql:queryConcat(q, ` WHERE status = ${status}`);
    }
    q = sql:queryConcat(q, ` ORDER BY id`);
    stream<Driver, sql:Error?> rs = dbClient->query(q);
    return from Driver d in rs
        select d;
}

// Going on/off shift. A BUSY driver is left alone, they have to finish the drop-off first,
// so false here means "driver is in the middle of a delivery".
function setDriverAvailability(int id, string status) returns boolean|error {
    sql:ExecutionResult res = check dbClient->execute(`
        UPDATE drivers SET status = ${status} WHERE id = ${id} AND status <> 'BUSY'`);
    return res.affectedRowCount == 1;
}

// Free drivers, longest idle first (never-assigned ones go to the front).
// That spreads the work around instead of always giving it to driver #1.
function availableDriverIds(int max) returns int[]|error {
    stream<IdRow, sql:Error?> rs = dbClient->query(`
        SELECT id FROM drivers WHERE status = 'AVAILABLE'
        ORDER BY last_assigned_at IS NOT NULL, last_assigned_at, id
        LIMIT ${max}`);
    return from IdRow r in rs
        select r.id;
}

// deliveries

function deliverySelect() returns sql:ParameterizedQuery =>
    `SELECT order_id AS orderId, customer_id AS customerId, restaurant_id AS restaurantId,
            delivery_address_id AS deliveryAddressId, driver_id AS driverId, status,
            DATE_FORMAT(ready_at, '%Y-%m-%dT%H:%i:%sZ') AS readyAt,
            DATE_FORMAT(assigned_at, '%Y-%m-%dT%H:%i:%sZ') AS assignedAt,
            DATE_FORMAT(picked_up_at, '%Y-%m-%dT%H:%i:%sZ') AS pickedUpAt,
            DATE_FORMAT(delivered_at, '%Y-%m-%dT%H:%i:%sZ') AS deliveredAt,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS createdAt,
            DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updatedAt
     FROM deliveries`;

function getDelivery(string orderId) returns Delivery|sql:Error {
    return dbClient->queryRow(sql:queryConcat(deliverySelect(), ` WHERE order_id = ${orderId}`));
}

function listDeliveries(string? status, int? driverId, int pageSize, int offset) returns Delivery[]|error {
    sql:ParameterizedQuery q = sql:queryConcat(deliverySelect(), ` WHERE 1=1`);
    if status is string {
        q = sql:queryConcat(q, ` AND status = ${status}`);
    }
    if driverId is int {
        q = sql:queryConcat(q, ` AND driver_id = ${driverId}`);
    }
    q = sql:queryConcat(q, ` ORDER BY created_at DESC LIMIT ${pageSize} OFFSET ${offset}`);
    stream<Delivery, sql:Error?> rs = dbClient->query(q);
    return from Delivery d in rs
        select d;
}

// Opens the delivery as soon as we hear about the order. INSERT IGNORE because Kafka can
// hand us the same orders.created twice, the primary key turns the repeat into a no-op.
function insertPendingDelivery(DeliveryRequest req) returns error? {
    sql:ExecutionResult res = check dbClient->execute(`
        INSERT IGNORE INTO deliveries (order_id, customer_id, restaurant_id, delivery_address_id, status)
        VALUES (${req.orderId}, ${req?.customerId}, ${req?.restaurantId}, ${req?.deliveryAddressId}, 'PENDING')`);
    if res.affectedRowCount == 1 {
        check insertEvent(req.orderId, PENDING, "Order received, waiting for the kitchen");
    }
}

// The kitchen is done, so the order joins the queue for a driver.
// Returns false when it was already queued (duplicate READY) or has moved on.
function markAwaitingDriver(string orderId) returns boolean|error {
    // we may have missed orders.created (service was down, topic trimmed, ...).
    // Better to deliver without knowing the customer than to leave the food on the counter.
    _ = check dbClient->execute(`
        INSERT IGNORE INTO deliveries (order_id, status) VALUES (${orderId}, 'PENDING')`);
    sql:ExecutionResult res = check dbClient->execute(`
        UPDATE deliveries SET status = 'AWAITING_DRIVER', ready_at = CURRENT_TIMESTAMP
        WHERE order_id = ${orderId} AND status = 'PENDING'`);
    if res.affectedRowCount != 1 {
        return false;
    }
    check insertEvent(orderId, AWAITING_DRIVER, "Order is ready, looking for a driver");
    return true;
}

// Orders still waiting for a driver, oldest first so nobody jumps the queue
function waitingOrderIds(int max) returns string[]|error {
    stream<OrderIdRow, sql:Error?> rs = dbClient->query(`
        SELECT order_id AS orderId FROM deliveries WHERE status = 'AWAITING_DRIVER'
        ORDER BY ready_at, created_at
        LIMIT ${max}`);
    return from OrderIdRow r in rs
        select r.orderId;
}

// Claims the driver and puts them on the delivery in one transaction.
// Both UPDATEs carry the expected status in the WHERE clause, so if another replica grabbed
// the driver (or the order) a moment earlier nothing matches, we roll back and return false.
function assignDriverTx(string orderId, int driverId) returns boolean|error {
    boolean done = false;
    transaction {
        sql:ExecutionResult claimed = check dbClient->execute(`
            UPDATE drivers SET status = 'BUSY', last_assigned_at = CURRENT_TIMESTAMP
            WHERE id = ${driverId} AND status = 'AVAILABLE'`);
        boolean ok = claimed.affectedRowCount == 1;
        if ok {
            sql:ExecutionResult attached = check dbClient->execute(`
                UPDATE deliveries SET driver_id = ${driverId}, status = 'ASSIGNED', assigned_at = CURRENT_TIMESTAMP
                WHERE order_id = ${orderId} AND status = 'AWAITING_DRIVER'`);
            ok = attached.affectedRowCount == 1;
        }
        if ok {
            _ = check dbClient->execute(`
                INSERT INTO delivery_events (order_id, status, note)
                VALUES (${orderId}, 'ASSIGNED', 'Driver assigned, heading to the restaurant')`);
            check commit;
            done = true;
        } else {
            rollback;
        }
    } on fail error e {
        return e;
    }
    return done;
}

// ASSIGNED -> OUT_FOR_DELIVERY: the driver has collected the food.
// false = the delivery wasn't in ASSIGNED any more (double tap in the app, or cancelled meanwhile).
function markPickedUp(string orderId) returns boolean|error {
    boolean done = false;
    transaction {
        sql:ExecutionResult res = check dbClient->execute(`
            UPDATE deliveries SET status = 'OUT_FOR_DELIVERY', picked_up_at = CURRENT_TIMESTAMP
            WHERE order_id = ${orderId} AND status = 'ASSIGNED'`);
        if res.affectedRowCount == 1 {
            _ = check dbClient->execute(`
                INSERT INTO delivery_events (order_id, status, note)
                VALUES (${orderId}, 'OUT_FOR_DELIVERY', 'Driver picked up the order')`);
            check commit;
            done = true;
        } else {
            rollback;
        }
    } on fail error e {
        return e;
    }
    return done;
}

// OUT_FOR_DELIVERY -> DELIVERED. The driver goes back into the pool in the same transaction,
// otherwise a crash in between would leave them BUSY forever with nothing to deliver.
function markDelivered(string orderId) returns boolean|error {
    boolean done = false;
    transaction {
        sql:ExecutionResult res = check dbClient->execute(`
            UPDATE deliveries SET status = 'DELIVERED', delivered_at = CURRENT_TIMESTAMP
            WHERE order_id = ${orderId} AND status = 'OUT_FOR_DELIVERY'`);
        if res.affectedRowCount == 1 {
            _ = check dbClient->execute(`
                UPDATE drivers d JOIN deliveries x ON x.driver_id = d.id
                SET d.status = 'AVAILABLE'
                WHERE x.order_id = ${orderId} AND d.status = 'BUSY'`);
            _ = check dbClient->execute(`
                INSERT INTO delivery_events (order_id, status, note)
                VALUES (${orderId}, 'DELIVERED', 'Order handed to the customer')`);
            check commit;
            done = true;
        } else {
            rollback;
        }
    } on fail error e {
        return e;
    }
    return done;
}

// The order was cancelled upstream. Only possible while the food hasn't left the restaurant.
// If a driver was already on the way they are released in the same transaction.
function cancelDelivery(string orderId) returns boolean|error {
    boolean done = false;
    transaction {
        // free the driver first, while the delivery row still says ASSIGNED
        _ = check dbClient->execute(`
            UPDATE drivers d JOIN deliveries x ON x.driver_id = d.id
            SET d.status = 'AVAILABLE'
            WHERE x.order_id = ${orderId} AND x.status = 'ASSIGNED' AND d.status = 'BUSY'`);
        sql:ExecutionResult res = check dbClient->execute(`
            UPDATE deliveries SET status = 'CANCELLED'
            WHERE order_id = ${orderId} AND status IN ('PENDING', 'AWAITING_DRIVER', 'ASSIGNED')`);
        if res.affectedRowCount == 1 {
            _ = check dbClient->execute(`
                INSERT INTO delivery_events (order_id, status, note)
                VALUES (${orderId}, 'CANCELLED', 'Order was cancelled')`);
            check commit;
            done = true;
        } else {
            rollback;
        }
    } on fail error e {
        return e;
    }
    return done;
}

// driver location

// Only the latest position is kept, that's all the tracking screen needs
function saveDriverLocation(int driverId, LocationUpdate loc) returns error? {
    _ = check dbClient->execute(`
        UPDATE drivers
        SET latitude = ${loc.latitude}, longitude = ${loc.longitude}, location_updated_at = CURRENT_TIMESTAMP
        WHERE id = ${driverId}`);
}

// The job a driver is on right now, or () when they are just driving around
function activeOrderForDriver(int driverId) returns string?|error {
    OrderIdRow|sql:Error row = dbClient->queryRow(`
        SELECT order_id AS orderId FROM deliveries
        WHERE driver_id = ${driverId} AND status IN ('ASSIGNED', 'OUT_FOR_DELIVERY')
        ORDER BY assigned_at DESC LIMIT 1`);
    if row is sql:NoRowsError {
        return ();
    }
    if row is sql:Error {
        return row;
    }
    return row.orderId;
}

// tracking timeline

function insertEvent(string orderId, string status, string? note) returns error? {
    _ = check dbClient->execute(`
        INSERT INTO delivery_events (order_id, status, note) VALUES (${orderId}, ${status}, ${note})`);
}

function listEvents(string orderId) returns TrackingEvent[]|error {
    stream<TrackingEvent, sql:Error?> rs = dbClient->query(`
        SELECT status, note, DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS occurredAt
        FROM delivery_events WHERE order_id = ${orderId} ORDER BY id`);
    return from TrackingEvent e in rs
        select e;
}
