import ballerina/http;
import ballerina/log;
import ballerina/sql;

listener http:Listener httpListener = new (servicePort);

service /payments on httpListener {
    resource function get [string orderId]()
            returns PaymentRecord|http:NotFound|http:InternalServerError {
        PaymentRecord|sql:Error payment = getPayment(orderId);
        if payment is PaymentRecord {
            return payment;
        }
        if payment is sql:NoRowsError {
            return <http:NotFound>{body: {code: "NOT_FOUND", message: "Payment not found"}};
        }
        log:printError("Payment lookup failed", payment, orderId = orderId);
        return <http:InternalServerError>{body: {code: "INTERNAL_ERROR", message: "Payment lookup failed"}};
    }
}

service /health on httpListener {
    resource function get .() returns json|http:ServiceUnavailable {
        int|error ping = dbClient->queryRow(`SELECT 1`);
        if ping is error {
            return <http:ServiceUnavailable>{body: {"status": "DOWN", "service": "payment-service"}};
        }
        return {"status": "UP", "service": "payment-service"};
    }
}
