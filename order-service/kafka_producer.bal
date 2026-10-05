import ballerina/log;
import ballerinax/kafka;

final kafka:Producer producer = check new (kafkaBootstrap, {
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

function publish(string topic, string key, json payload) returns error? {
    check producer->send({
        topic: topic,
        key: key.toBytes(),
        value: payload.toJsonString().toBytes()
    });
}

public function publishOrderCreated(OrderRecord o) {
    OrderCreatedEvent ev = {
        orderId: o.orderId,
        customerId: o.customerId,
        restaurantId: o.restaurantId,
        totalAmount: o.totalAmount,
        deliveryAddressId: o.deliveryAddressId,
        items: o.items
    };
    error? e = publish(topicOrderCreated, o.orderId, ev.toJson());
    if e is error {
        log:printError("failed to publish orders.created", e, orderId = o.orderId);
    }
}

public function publishStatusChanged(string orderId, string status) {
    OrderStatusEvent ev = {orderId, status};
    error? e = publish(topicOrderStatusChanged, orderId, ev.toJson());
    if e is error {
        log:printError("failed to publish orders.status.changed", e, orderId = orderId);
    }
}
