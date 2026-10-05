import ballerina/log;
import ballerinax/kafka;

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, {
    clientId: "payment-service-producer",
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

function publishPaymentResult(PaymentRecord payment) returns error? {
    PaymentEvent event = {orderId: payment.orderId};
    string topic = payment.status == "COMPLETED" ? paymentCompletedTopic : paymentFailedTopic;
    check kafkaProducer->send({
        topic,
        key: payment.orderId.toBytes(),
        value: event.toJsonString().toBytes()
    });
    log:printInfo("Published payment result", orderId = payment.orderId, status = payment.status);
}
