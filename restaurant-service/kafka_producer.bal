import ballerina/log;
import ballerina/time;
import ballerinax/kafka;

// Publishes restaurants.order.status and restaurants.stock.low.
// acks=all + retries so a broker-accepted event isn't lost. Keyed by orderId /
// restaurantId so related events stay in one partition and keep their order.

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, {
    clientId: "restaurant-service-producer",
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

# Tells the Order Service what the kitchen decided (CONFIRMED, REJECTED, PREPARING, READY).
# Best effort: a Kafka outage is logged, it never fails the HTTP call or the consumer loop.
function publishOrderStatus(string orderId, int restaurantId, string status, string? reason = ()) {
    RestaurantOrderEvent evt = {
        eventType: "RESTAURANT_ORDER_" + status,
        orderId,
        restaurantId,
        status,
        reason,
        occurredAt: time:utcToString(time:utcNow())
    };
    error? result = kafkaProducer->send({
        topic: restaurantOrderTopic,
        key: orderId.toBytes(),
        value: evt.toJsonString().toBytes()
    });
    if result is error {
        log:printError("Failed to publish restaurants.order.status", result, orderId = orderId, status = status);
    } else {
        log:printInfo("Published restaurants.order.status", orderId = orderId, status = status);
    }
}

# For the Notification Service: an item is running low (or sold out).
function publishLowStock(MenuItem item) {
    LowStockEvent evt = {
        eventType: "STOCK_LOW",
        restaurantId: item.restaurantId,
        menuItemId: item.id,
        itemName: item.name,
        stockQuantity: item.stockQuantity,
        occurredAt: time:utcToString(time:utcNow())
    };
    error? result = kafkaProducer->send({
        topic: lowStockTopic,
        key: item.restaurantId.toString().toBytes(),
        value: evt.toJsonString().toBytes()
    });
    if result is error {
        log:printError("Failed to publish restaurants.stock.low", result, menuItemId = item.id);
    } else {
        log:printInfo("Published restaurants.stock.low", menuItemId = item.id, left = item.stockQuantity);
    }
}
