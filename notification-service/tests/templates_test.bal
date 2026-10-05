import ballerina/test;

// Pure checks on the message wording and validation. `bal test` still needs MySQL + Kafka up,
// because the module creates its DB client and Kafka listener at start-up.

@test:Config {}
function longOrderIdsAreShortened() {
    test:assertEquals(shortId("3f2b9c1e-77aa-4c0d-9a51-0d5e2b7c1f00"), "#3f2b9c1e");
    test:assertEquals(shortId("order-1"), "#order-1");
}

@test:Config {}
function everyOrderStatusWeAnnounceHasText() {
    foreach string status in ["CONFIRMED", "PREPARING", "READY", "OUT_FOR_DELIVERY", "DELIVERED", "CANCELLED"] {
        test:assertTrue(orderStatusText("order-1", status) is [string, string], status + " has no message");
    }
}

@test:Config {}
function createdAndUnknownStatusesAreSilent() {
    test:assertTrue(orderStatusText("order-1", "CREATED") is ());
    test:assertTrue(orderStatusText("order-1", "SHIPPED") is ());
}

@test:Config {}
function soldOutReadsDifferentlyFromLow() {
    test:assertEquals(lowStockText("Kapana roll", 0)[0], "Sold out");
    test:assertEquals(lowStockText("Kapana roll", 3)[0], "Stock running low");
}

@test:Config {}
function manualNotificationIsValidated() {
    ManualNotification ok = {recipientType: "customer", recipientId: 1, title: "Hi", message: "Hello there"};
    test:assertEquals(validateManual(ok), ());
    test:assertTrue(validateManual({recipientType: "ALIEN", recipientId: 1, title: "Hi", message: "x"}) is string);
    test:assertTrue(validateManual({recipientType: "DRIVER", recipientId: 0, title: "Hi", message: "x"}) is string);
    test:assertTrue(validateManual({recipientType: "DRIVER", recipientId: 1, title: " ", message: "x"}) is string);
}
