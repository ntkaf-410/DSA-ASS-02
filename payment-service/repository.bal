import ballerina/sql;

function paymentSelect() returns sql:ParameterizedQuery =>
    `SELECT order_id AS orderId, customer_id AS customerId, amount, currency, status,
            failure_reason AS failureReason,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS createdAt,
            DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updatedAt
     FROM payments`;

function getPayment(string orderId) returns PaymentRecord|sql:Error {
    return dbClient->queryRow(sql:queryConcat(paymentSelect(), ` WHERE order_id = ${orderId}`));
}

// The primary key makes repeated orders and created deliveries safe. The caller loads the stored result afterward and republishes it if necessary.
function recordPayment(OrderCreatedEvent event) returns PaymentRecord|error {
    string status = paymentStatus(event.totalAmount, simulatePaymentFailure);
    string? reason = status == "FAILED"
        ? (simulatePaymentFailure ? "Payment declined by simulation" : "Payment amount must be positive")
        : ();
    _ = check dbClient->execute(`
        INSERT IGNORE INTO payments (order_id, customer_id, amount, status, failure_reason)
        VALUES (${event.orderId}, ${event.customerId}, ${event.totalAmount}, ${status}, ${reason})`);
    return getPayment(event.orderId);
}
