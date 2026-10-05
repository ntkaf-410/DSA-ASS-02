import ballerina/log;

// Driver assignment.
// The rule is simple: the free driver who has been idle the longest gets the next order.
// If nobody is free the delivery waits in AWAITING_DRIVER and is picked up again
// the moment a driver comes online or finishes a drop-off.

// Entry point when an order is ready for pickup (Kafka READY, or the manual REST fallback).
// Safe to call twice for the same order.
function requestDelivery(string orderId) returns Delivery|error {
    boolean queued = check markAwaitingDriver(orderId);
    if queued {
        log:printInfo("Delivery queued for a driver", orderId = orderId);
    }
    Delivery delivery = check getDelivery(orderId);
    if delivery.status != AWAITING_DRIVER {
        // already assigned / on the road / cancelled - a repeated READY changes nothing
        return delivery;
    }
    Driver? driver = check assignDriver(orderId);
    if driver is () {
        log:printWarn("No driver available, delivery stays queued", orderId = orderId);
        return delivery;
    }
    return getDelivery(orderId);
}

// Tries the free drivers one by one. Returns () when none could be claimed.
function assignDriver(string orderId) returns Driver?|error {
    int[] candidates = check availableDriverIds(maxAssignAttempts);
    foreach int driverId in candidates {
        boolean assigned = check assignDriverTx(orderId, driverId);
        if assigned {
            return check announceAssignment(orderId, driverId);
        }
        // Didn't stick. Either someone else took this driver (try the next one)
        // or the order itself is no longer waiting (then there's nothing left to do).
        Delivery delivery = check getDelivery(orderId);
        if delivery.status != AWAITING_DRIVER {
            return ();
        }
    }
    return ();
}

// Admin picked the driver by hand. Same transaction as the automatic path,
// we just don't fall through to another driver if this one is taken.
function assignSpecificDriver(string orderId, int driverId) returns Driver|error {
    boolean assigned = check assignDriverTx(orderId, driverId);
    if !assigned {
        return error AssignmentConflict("Driver is not available or the delivery is no longer waiting for one");
    }
    return announceAssignment(orderId, driverId);
}

function announceAssignment(string orderId, int driverId) returns Driver|error {
    Driver driver = check getDriver(driverId);
    Delivery delivery = check getDelivery(orderId);
    log:printInfo("Driver assigned", orderId = orderId, driverId = driverId, driver = driver.fullName);
    publishDriverAssigned(delivery, driver);
    return driver;
}

// A driver just became free: work through the queue, oldest order first, until we run out
// of drivers. Called after going online and after a completed drop-off.
function assignWaitingDeliveries() {
    string[]|error waiting = waitingOrderIds(maxAssignAttempts);
    if waiting is error {
        log:printError("Could not read the delivery queue", waiting);
        return;
    }
    foreach string orderId in waiting {
        Driver?|error driver = assignDriver(orderId);
        if driver is error {
            log:printError("Assigning a queued delivery failed", driver, orderId = orderId);
            return;
        }
        if driver is () {
            // no drivers left, the rest of the queue has to keep waiting
            return;
        }
    }
}
