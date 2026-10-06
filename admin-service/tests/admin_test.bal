import ballerina/test;

// Only the pure helpers are tested here, the reports themselves need MySQL and Kafka running.

@test:Config {}
function averageIsRoundedToCents() {
    test:assertEquals(averageOf(100d, 3), 33.33d);
}

@test:Config {}
function averageOfNothingIsZero() {
    test:assertEquals(averageOf(0d, 0), 0d);
}

@test:Config {}
function numbersAreAcceptedAsTextToo() {
    // one service sends restaurantId as 3, another as "3"
    map<json> evt = {"restaurantId": "3", "customerId": 7, "totalAmount": "125.50"};
    test:assertEquals(intOf(evt, "restaurantId"), 3);
    test:assertEquals(intOf(evt, "customerId"), 7);
    test:assertEquals(decimalOf(evt, "totalAmount"), 125.50d);
}

@test:Config {}
function missingAndBlankFieldsAreNil() {
    map<json> evt = {"orderId": "  ", "reason": null};
    test:assertEquals(textOf(evt, "orderId"), ());
    test:assertEquals(textOf(evt, "reason"), ());
    test:assertEquals(intOf(evt, "driverId"), ());
    test:assertTrue(requireText(evt, "orderId") is error);
}

@test:Config {}
function limitsAreBounded() {
    test:assertEquals(validateLimit(10), ());
    test:assertTrue(validateLimit(0) is string);
    test:assertTrue(validateLimit(101) is string);
}
