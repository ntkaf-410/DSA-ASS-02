import ballerina/test;

@test:Config {}
function positiveAmountCompletesByDefault() {
    test:assertEquals(paymentStatus(125.50d, false), "COMPLETED");
}

@test:Config {}
function failureCanBeSimulated() {
    test:assertEquals(paymentStatus(125.50d, true), "FAILED");
}

@test:Config {}
function nonPositiveAmountFails() {
    test:assertEquals(paymentStatus(0d, false), "FAILED");
}
