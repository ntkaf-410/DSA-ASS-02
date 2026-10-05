import ballerina/lang.value;
import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener orderEventsListener = new (kafkaBootstrap, {
    groupId: consumerGroupId,
    topics: [orderCreatedTopic],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: true
});

service on orderEventsListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            do {
                string body = check string:fromBytes(rec.value);
                json payload = check value:fromJsonString(body);
                check handleOrderCreated(payload);
            } on fail error e {
                log:printError("Failed to process orders.created record", e);
            }
        }
    }
}

function handleOrderCreated(json payload) returns error? {
    OrderCreatedEvent event = check payload.cloneWithType();
    if event.orderId.trim().length() == 0 {
        return error("orders.created has an empty orderId");
    }
    if event.totalAmount < 0d {
        return error("orders.created has a negative totalAmount");
    }

    PaymentRecord|error stored = recordPayment(event);
    if stored is error {
        return stored;
    }
    // Republish the persisted result on duplicate deliveries. This also
    // recovers when the database commit succeeded but Kafka was unavailable.
    check publishPaymentResult(stored);
}
