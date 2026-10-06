import ballerina/http;
import ballerina/log;
import ballerina/sql;

// REST API of the Delivery Service, order side. Base path /deliveries.
// A delivery is identified by the orderId, there is exactly one per order.

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /deliveries on httpListener {

    // Manual fallback: asks for a driver without going through Kafka.
    // Normally orders.created opens the delivery and the kitchen's READY queues it,
    // this is for demos and for the day the broker is down.
    resource function post .(@http:Payload DeliveryRequest payload)
            returns http:Created|http:BadRequest|http:InternalServerError {
        if payload.orderId.trim().length() == 0 {
            return badRequest("orderId is required");
        }
        error? opened = insertPendingDelivery(payload);
        if opened is error {
            log:printError("Could not open delivery", opened, orderId = payload.orderId);
            return internalError();
        }
        Delivery|error delivery = requestDelivery(payload.orderId);
        if delivery is error {
            log:printError("Delivery request failed", delivery, orderId = payload.orderId);
            return internalError();
        }
        return <http:Created>{
            headers: {"Location": string `/deliveries/${payload.orderId}`},
            body: delivery
        };
    }

    // Optional ?status= and ?driverId= filters. ?status=AWAITING_DRIVER is the live queue.
    resource function get .(string? status, int? driverId, int page = 1, int pageSize = 20)
            returns Delivery[]|http:BadRequest|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        string? wanted = status is string ? status.trim().toUpperAscii() : ();
        if wanted is string && DELIVERY_STATUSES.indexOf(wanted) is () {
            return badRequest("unknown delivery status " + wanted);
        }
        Delivery[]|error list = listDeliveries(wanted, driverId, pageSize, (page - 1) * pageSize);
        if list is error {
            log:printError("Listing deliveries failed", list);
            return internalError();
        }
        return list;
    }

    resource function get [string orderId]() returns Delivery|http:NotFound|http:InternalServerError {
        Delivery|sql:Error delivery = getDelivery(orderId);
        if delivery is sql:NoRowsError {
            return notFound(string `No delivery for order ${orderId}`);
        }
        if delivery is sql:Error {
            log:printError("Delivery lookup failed", delivery, orderId = orderId);
            return internalError();
        }
        return delivery;
    }

    // Admin override. Body {} lets the service choose, {"driverId": 3} forces a specific driver.
    resource function post [string orderId]/assign(@http:Payload AssignRequest payload)
            returns Delivery|http:NotFound|http:Conflict|http:InternalServerError {
        Delivery|sql:Error current = getDelivery(orderId);
        if current is sql:NoRowsError {
            return notFound(string `No delivery for order ${orderId}`);
        }
        if current is sql:Error {
            log:printError("Delivery lookup failed", current, orderId = orderId);
            return internalError();
        }
        if current.status != PENDING && current.status != AWAITING_DRIVER {
            return conflictResponse(string `Delivery is already ${current.status}`);
        }
        // an admin assigning by hand means the food is (about to be) ready, so skip the wait for READY
        boolean|error queued = markAwaitingDriver(orderId);
        if queued is error {
            log:printError("Could not queue delivery", queued, orderId = orderId);
            return internalError();
        }

        int? driverId = payload?.driverId;
        if driverId is int {
            Driver|error chosen = assignSpecificDriver(orderId, driverId);
            if chosen is AssignmentConflict {
                return conflictResponse(chosen.message());
            }
            if chosen is sql:NoRowsError {
                return notFound(string `Driver ${driverId} not found`);
            }
            if chosen is error {
                log:printError("Manual assignment failed", chosen, orderId = orderId, driverId = driverId);
                return internalError();
            }
        } else {
            Driver?|error picked = assignDriver(orderId);
            if picked is error {
                log:printError("Assignment failed", picked, orderId = orderId);
                return internalError();
            }
            if picked is () {
                return conflictResponse("No driver is available right now, the delivery stays in the queue");
            }
        }

        Delivery|sql:Error updated = getDelivery(orderId);
        if updated is sql:Error {
            log:printError("Could not reload delivery", updated, orderId = orderId);
            return internalError();
        }
        return updated;
    }

    // Driver app: OUT_FOR_DELIVERY when the food is collected, DELIVERED at the door.
    // Everything before that is set by the service itself, not through this endpoint.
    resource function put [string orderId]/status(@http:Payload DeliveryStatusUpdate payload)
            returns Delivery|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        string next = payload.status.trim().toUpperAscii();
        if next != OUT_FOR_DELIVERY && next != DELIVERED {
            return badRequest("status must be OUT_FOR_DELIVERY or DELIVERED");
        }
        Delivery|error updated = updateDeliveryStatus(orderId, next);
        if updated is sql:NoRowsError {
            return notFound(string `No delivery for order ${orderId}`);
        }
        if updated is InvalidTransition {
            return conflictResponse(updated.message());
        }
        if updated is error {
            log:printError("Delivery status update failed", updated, orderId = orderId, status = next);
            return internalError();
        }
        return updated;
    }

    // Customer app polls this: current status, who the driver is, where they are, and the timeline so far
    resource function get [string orderId]/tracking()
            returns TrackingView|http:NotFound|http:InternalServerError {
        TrackingView|error view = buildTracking(orderId);
        if view is sql:NoRowsError {
            return notFound(string `No delivery for order ${orderId}`);
        }
        if view is error {
            log:printError("Tracking lookup failed", view, orderId = orderId);
            return internalError();
        }
        return view;
    }
}
