import ballerina/lang.runtime;
import ballerina/lang.value;
import ballerina/log;
import ballerinax/kafka;


// kafka_consumer.bal - builds the customer's order-history read model from
// Order Service events. Processing is idempotent (see upsertOrder) so Kafka's
// at-least-once delivery is safe.

listener kafka:Listener orderEventsListener = new (kafkaBootstrap, {
    groupId: consumerGroupId,
    topics: [orderCreatedTopic, orderStatusTopic],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: true
});

service on orderEventsListener {

    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            string topic = rec.offset.partition.topic;
            // One bad message must never block the partition -> catch per record.
            do {
                string body = check string:fromBytes(rec.value);
                json payload = check value:fromJsonString(body);
                if topic == orderCreatedTopic {
                    check handleOrderCreated(payload);
                } else if topic == orderStatusTopic {
                    check handleOrderStatusChanged(payload);
                }
            } on fail error e {
                log:printError("Failed to process Kafka record", e, topic = topic);
            }
        }
    }
}

function handleOrderCreated(json payload) returns error? {
    OrderCreatedEvent evt = check payload.cloneWithType();
    boolean exists = check customerExists(evt.customerId);
    if !exists {
        log:printWarn("orders.created for unknown customer - ignored",
            orderId = evt.orderId, customerId = evt.customerId);
        return;
    }
    check upsertOrder(evt);
    log:printInfo("Order stored in history", orderId = evt.orderId, customerId = evt.customerId);
}

function handleOrderStatusChanged(json payload) returns error? {
    OrderStatusEvent evt = check payload.cloneWithType();
    if VALID_STATUSES.indexOf(evt.status) is () {
        log:printWarn("Ignoring unknown order status", orderId = evt.orderId, status = evt.status);
        return;
    }
    // Different topics have no cross-topic ordering, so a status change can
    // arrive just before the matching "created" event: retry briefly.
    int attempt = 0;
    while attempt < 3 {
        int rows = check updateOrderStatus(evt.orderId, evt.status);
        if rows > 0 {
            log:printInfo("Order status updated", orderId = evt.orderId, status = evt.status);
            return;
        }
        attempt += 1;
        runtime:sleep(0.5);
    }
    log:printWarn("Status change for unknown order", orderId = evt.orderId, status = evt.status);
}
