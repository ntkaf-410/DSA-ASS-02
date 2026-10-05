import ballerina/test;

// Pure checks on the delivery lifecycle. `bal test` still needs MySQL + Kafka up,
// because the module creates its DB client and Kafka producer at start-up.

@test:Config {}
function happyPathIsAllowed() {
    test:assertTrue(canMove(PENDING, AWAITING_DRIVER));
    test:assertTrue(canMove(AWAITING_DRIVER, ASSIGNED));
    test:assertTrue(canMove(ASSIGNED, OUT_FOR_DELIVERY));
    test:assertTrue(canMove(OUT_FOR_DELIVERY, DELIVERED));
}

@test:Config {}
function cancelOnlyBeforePickup() {
    test:assertTrue(canMove(PENDING, CANCELLED));
    test:assertTrue(canMove(AWAITING_DRIVER, CANCELLED));
    test:assertTrue(canMove(ASSIGNED, CANCELLED));
    test:assertFalse(canMove(OUT_FOR_DELIVERY, CANCELLED));
    test:assertFalse(canMove(DELIVERED, CANCELLED));
}

@test:Config {}
function stepsCannotBeSkippedOrReversed() {
    test:assertFalse(canMove(PENDING, DELIVERED));
    test:assertFalse(canMove(ASSIGNED, DELIVERED));
    test:assertFalse(canMove(DELIVERED, OUT_FOR_DELIVERY));
    test:assertFalse(canMove(CANCELLED, ASSIGNED));
    test:assertFalse(canMove("NOPE", ASSIGNED));
}

@test:Config {}
function locationMustBeOnTheGlobe() {
    test:assertEquals(validateLocation({latitude: -22.5609, longitude: 17.0658}), ());
    test:assertTrue(validateLocation({latitude: 91, longitude: 17.0658}) is string);
    test:assertTrue(validateLocation({latitude: -22.5609, longitude: -181}) is string);
}
