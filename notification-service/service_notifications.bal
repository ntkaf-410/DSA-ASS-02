import ballerina/http;
import ballerina/log;
import ballerina/sql;

// REST API of the Notification Service. Base path /notifications, port 8086.
// Mostly read-only: notifications are created from Kafka events, this is the inbox on top.

listener http:Listener httpListener = new (servicePort);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /notifications on httpListener {

    // Send something by hand (admin announcement, support message, ...).
    // Goes through the same notifier as the Kafka events, so customers still get it by e-mail.
    resource function post .(@http:Payload ManualNotification payload)
            returns http:Created|http:BadRequest|http:InternalServerError {
        string? invalid = validateManual(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        int?|error id = notify({
            recipientType: payload.recipientType.trim().toUpperAscii(),
            recipientId: payload.recipientId,
            orderId: payload?.orderId,
            eventType: "MANUAL",
            title: payload.title.trim(),
            message: payload.message.trim()
        });
        if id is error {
            log:printError("Manual notification failed", id);
            return internalError();
        }
        if id is () {
            // manual messages have no dedupe key so this can't really happen, but the type says it might
            return internalError();
        }
        Notification|sql:Error created = getNotification(id);
        if created is sql:Error {
            log:printError("Could not load created notification", created, notificationId = id);
            return internalError();
        }
        return <http:Created>{
            headers: {"Location": string `/notifications/${id}`},
            body: created
        };
    }

    // Everything, newest first. Filters: ?recipientType=CUSTOMER|DRIVER|RESTAURANT, ?recipientId=, ?unreadOnly=true
    resource function get .(string? recipientType, int? recipientId, boolean unreadOnly = false,
            int page = 1, int pageSize = 20) returns Notification[]|http:BadRequest|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        string? wanted = recipientType is string ? recipientType.trim().toUpperAscii() : ();
        if wanted is string && RECIPIENT_TYPES.indexOf(wanted) is () {
            return badRequest("recipientType must be CUSTOMER, DRIVER or RESTAURANT");
        }
        Notification[]|error list = listNotifications(wanted, recipientId, unreadOnly, pageSize, (page - 1) * pageSize);
        if list is error {
            log:printError("Listing notifications failed", list);
            return internalError();
        }
        return list;
    }

    resource function get [int id]() returns Notification|http:NotFound|http:InternalServerError {
        Notification|sql:Error n = getNotification(id);
        if n is sql:NoRowsError {
            return notFound(string `Notification ${id} not found`);
        }
        if n is sql:Error {
            log:printError("Notification lookup failed", n, notificationId = id);
            return internalError();
        }
        return n;
    }

    resource function put [int id]/read() returns Notification|http:NotFound|http:InternalServerError {
        boolean|error found = markRead(id);
        if found is error {
            log:printError("Mark-read failed", found, notificationId = id);
            return internalError();
        }
        if !found {
            return notFound(string `Notification ${id} not found`);
        }
        Notification|sql:Error n = getNotification(id);
        if n is sql:Error {
            log:printError("Could not reload notification", n, notificationId = id);
            return internalError();
        }
        return n;
    }

    // The customer app's inbox. Same as the list above with the customer filter filled in.
    resource function get customers/[int customerId](boolean unreadOnly = false, int page = 1, int pageSize = 20)
            returns Notification[]|http:BadRequest|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        Notification[]|error list = listNotifications(CUSTOMER, customerId, unreadOnly, pageSize, (page - 1) * pageSize);
        if list is error {
            log:printError("Listing customer notifications failed", list, customerId = customerId);
            return internalError();
        }
        return list;
    }

    // the number on the little bell icon
    resource function get customers/[int customerId]/unread\-count()
            returns UnreadCount|http:InternalServerError {
        int|error unread = countUnread(customerId);
        if unread is error {
            log:printError("Unread count failed", unread, customerId = customerId);
            return internalError();
        }
        return {customerId, unread};
    }

    // "mark all as read"
    resource function put customers/[int customerId]/read() returns UnreadCount|http:InternalServerError {
        error? done = markAllRead(customerId);
        if done is error {
            log:printError("Mark-all-read failed", done, customerId = customerId);
            return internalError();
        }
        return {customerId, unread: 0};
    }
}

// Used by the Docker healthcheck and by the admin/infra side
service /health on httpListener {
    resource function get .() returns json|http:ServiceUnavailable {
        int|error ping = dbClient->queryRow(`SELECT 1`);
        if ping is error {
            return <http:ServiceUnavailable>{body: {"status": "DOWN", "service": "notification-service"}};
        }
        return {"status": "UP", "service": "notification-service"};
    }
}
