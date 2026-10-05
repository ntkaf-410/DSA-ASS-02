import ballerina/sql;

// Every SQL statement lives here, all parameterised. Handlers and Kafka code never build SQL.

// contacts

// Last write wins, so a customer who changes their e-mail and re-registers still gets mail
function upsertContact(Contact c) returns error? {
    _ = check dbClient->execute(`
        INSERT INTO contacts (customer_id, full_name, email, phone)
        VALUES (${c.customerId}, ${c.fullName}, ${c.email}, ${c.phone})
        ON DUPLICATE KEY UPDATE full_name = VALUES(full_name), email = VALUES(email), phone = VALUES(phone)`);
}

function getContact(int customerId) returns Contact|sql:Error {
    return dbClient->queryRow(`
        SELECT customer_id AS customerId, full_name AS fullName, email, phone
        FROM contacts WHERE customer_id = ${customerId}`);
}

// order -> customer lookup

function saveOrderRef(OrderRef r) returns error? {
    _ = check dbClient->execute(`
        INSERT IGNORE INTO order_refs (order_id, customer_id, restaurant_id)
        VALUES (${r.orderId}, ${r.customerId}, ${r.restaurantId})`);
}

function getOrderRef(string orderId) returns OrderRef|sql:Error {
    return dbClient->queryRow(`
        SELECT order_id AS orderId, customer_id AS customerId, restaurant_id AS restaurantId
        FROM order_refs WHERE order_id = ${orderId}`);
}

// notifications

function notificationSelect() returns sql:ParameterizedQuery =>
    `SELECT id, recipient_type AS recipientType, recipient_id AS recipientId, order_id AS orderId,
            event_type AS eventType, channel, destination, title, message, status,
            is_read AS isRead,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS createdAt
     FROM notifications`;

// Returns the new id, or () when a notification with the same dedupe key is already there.
// The UNIQUE key does the work, so two replicas handling the same message can't both insert.
function insertNotification(Draft d, string channel, string? destination) returns int?|error {
    sql:ExecutionResult res = check dbClient->execute(`
        INSERT IGNORE INTO notifications
            (recipient_type, recipient_id, order_id, event_type, channel, destination, title, message, dedupe_key)
        VALUES (${d.recipientType}, ${d.recipientId}, ${d.orderId}, ${d.eventType}, ${channel}, ${destination},
                ${d.title}, ${d.message}, ${d.dedupeKey})`);
    if res.affectedRowCount != 1 {
        return ();
    }
    string|int? id = res.lastInsertId;
    if id is int {
        return id;
    }
    return error("Could not read generated notification id");
}

function getNotification(int id) returns Notification|sql:Error {
    return dbClient->queryRow(sql:queryConcat(notificationSelect(), ` WHERE id = ${id}`));
}

// Newest first, that's how an inbox reads
function listNotifications(string? recipientType, int? recipientId, boolean unreadOnly, int pageSize, int offset)
        returns Notification[]|error {
    sql:ParameterizedQuery q = sql:queryConcat(notificationSelect(), ` WHERE 1=1`);
    if recipientType is string {
        q = sql:queryConcat(q, ` AND recipient_type = ${recipientType}`);
    }
    if recipientId is int {
        q = sql:queryConcat(q, ` AND recipient_id = ${recipientId}`);
    }
    if unreadOnly {
        q = sql:queryConcat(q, ` AND is_read = FALSE`);
    }
    q = sql:queryConcat(q, ` ORDER BY id DESC LIMIT ${pageSize} OFFSET ${offset}`);
    stream<Notification, sql:Error?> rs = dbClient->query(q);
    return from Notification n in rs
        select n;
}

// false = no such notification
function markRead(int id) returns boolean|error {
    sql:ExecutionResult res = check dbClient->execute(`
        UPDATE notifications SET is_read = TRUE WHERE id = ${id}`);
    return res.affectedRowCount == 1;
}

function markAllRead(int customerId) returns error? {
    _ = check dbClient->execute(`
        UPDATE notifications SET is_read = TRUE
        WHERE recipient_type = 'CUSTOMER' AND recipient_id = ${customerId} AND is_read = FALSE`);
}

function countUnread(int customerId) returns int|error {
    return dbClient->queryRow(`
        SELECT COUNT(*) FROM notifications
        WHERE recipient_type = 'CUSTOMER' AND recipient_id = ${customerId} AND is_read = FALSE`);
}
