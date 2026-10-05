import ballerina/log;

// Delivery tracking: the status lifecycle, the driver's live position and the
// timeline the customer sees.
//
//   PENDING -> AWAITING_DRIVER -> ASSIGNED -> OUT_FOR_DELIVERY -> DELIVERED
//
// CANCELLED is possible until the driver has the food. After that the order is on the
// road and the Order Service doesn't allow a cancel either, so the two stay in step.

final readonly & map<string[]> DELIVERY_TRANSITIONS = {
    "PENDING": [AWAITING_DRIVER, CANCELLED],
    "AWAITING_DRIVER": [ASSIGNED, CANCELLED],
    "ASSIGNED": [OUT_FOR_DELIVERY, CANCELLED],
    "OUT_FOR_DELIVERY": [DELIVERED],
    "DELIVERED": [],
    "CANCELLED": []
};

function canMove(string current, string next) returns boolean {
    string[]? allowed = DELIVERY_TRANSITIONS[current];
    if allowed is () {
        return false;
    }
    return allowed.indexOf(next) is int;
}

// The driver app calls this twice per job: "I have the food" (OUT_FOR_DELIVERY)
// and "I handed it over" (DELIVERED).
function updateDeliveryStatus(string orderId, string next) returns Delivery|error {
    Delivery current = check getDelivery(orderId);
    if !canMove(current.status, next) {
        return error InvalidTransition(string `Cannot move a delivery from ${current.status} to ${next}`);
    }

    boolean changed = false;
    if next == OUT_FOR_DELIVERY {
        changed = check markPickedUp(orderId);
    } else if next == DELIVERED {
        changed = check markDelivered(orderId);
    }
    if !changed {
        // somebody else moved it between our read and our write
        return error InvalidTransition("Delivery was updated in the meantime, reload and try again");
    }

    Delivery updated = check getDelivery(orderId);
    log:printInfo("Delivery status changed", orderId = orderId, status = next);
    publishDeliveryStatus(updated);
    if next == DELIVERED {
        // this driver is free again, give them the next order in the queue if there is one
        assignWaitingDeliveries();
    }
    return updated;
}

// GPS ping from the driver app. We always remember where the driver is, and if they are
// on a job the position also goes out on Kafka so the customer can follow it live.
function recordDriverLocation(int driverId, LocationUpdate loc) returns Driver|error {
    // fails with NoRowsError for an unknown driver, the handler turns that into a 404
    _ = check getDriver(driverId);
    check saveDriverLocation(driverId, loc);
    string? orderId = check activeOrderForDriver(driverId);
    if orderId is string {
        publishDriverLocation(orderId, driverId, loc);
    }
    return getDriver(driverId);
}

// Everything the "where is my food" screen needs in one call.
function buildTracking(string orderId) returns TrackingView|error {
    Delivery delivery = check getDelivery(orderId);
    DriverSummary? driver = ();
    int? driverId = delivery.driverId;
    if driverId is int {
        Driver d = check getDriver(driverId);
        // The position is only shared while the driver is on THIS job. Once it's delivered
        // they are off to someone else and it's none of this customer's business.
        boolean live = delivery.status == ASSIGNED || delivery.status == OUT_FOR_DELIVERY;
        driver = {
            id: d.id,
            fullName: d.fullName,
            phone: d.phone,
            vehicle: d.vehicle,
            plateNumber: d.plateNumber,
            latitude: live ? d.latitude : (),
            longitude: live ? d.longitude : (),
            locationUpdatedAt: live ? d.locationUpdatedAt : ()
        };
    }
    return {
        orderId: delivery.orderId,
        status: delivery.status,
        driver,
        timeline: check listEvents(orderId)
    };
}
