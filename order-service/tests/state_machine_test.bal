import ballerina/test;

@test:Config {}
function testHappyPath() {
    test:assertTrue(canTransition("CREATED", "CONFIRMED"));
    test:assertTrue(canTransition("CONFIRMED", "PREPARING"));
    test:assertTrue(canTransition("PREPARING", "READY"));
    test:assertTrue(canTransition("READY", "OUT_FOR_DELIVERY"));
    test:assertTrue(canTransition("OUT_FOR_DELIVERY", "DELIVERED"));
}

@test:Config {}
function testCancelOnlyBeforePreparing() {
    test:assertTrue(canTransition("CREATED", "CANCELLED"));
    test:assertTrue(canTransition("CONFIRMED", "CANCELLED"));
    test:assertFalse(canTransition("PREPARING", "CANCELLED"));
    test:assertFalse(canTransition("OUT_FOR_DELIVERY", "CANCELLED"));
}

@test:Config {}
function testIllegalMovesRejected() {
    test:assertFalse(canTransition("CREATED", "DELIVERED"));
    test:assertFalse(canTransition("DELIVERED", "CREATED"));
    test:assertFalse(canTransition("CANCELLED", "CONFIRMED"));
    test:assertFalse(canTransition("NOPE", "CONFIRMED"));
}

@test:Config {}
function testValidStatus() {
    test:assertTrue(isValidStatus("READY"));
    test:assertFalse(isValidStatus("SHIPPED"));
}
