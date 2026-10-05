import ballerina/lang.value;
import ballerina/log;
import ballerina/sql;
import ballerinax/kafka;

// Consumes orders.created (reserve stock, confirm or reject) and
// orders.status.changed (give stock back on CANCELLED).
// Our own consumer group, so the Customer Service and this one each get every message.

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
            // catch per record so one bad message can't block the partition
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
    OrderRequest req = check parseOrderCreated(payload);

    // Kafka is at-least-once, so the same order can show up twice
    boolean seen = check kitchenOrderExists(req.orderId);
    if seen {
        log:printInfo("Duplicate orders.created ignored", orderId = req.orderId);
        return;
    }

    Restaurant|sql:Error restaurant = getRestaurant(req.restaurantId);
    if restaurant is sql:NoRowsError {
        return rejectOrder(req, "Restaurant not found");
    }
    if restaurant is sql:Error {
        return restaurant;
    }
    if !restaurant.isActive {
        return rejectOrder(req, "Restaurant is not accepting orders");
    }

    OpeningHours[] hours = check listOpeningHours(req.restaurantId);
    if !isOpenNow(hours) {
        return rejectOrder(req, "Restaurant is closed right now");
    }

    string?|error failure = acceptOrder(req);
    if failure is error {
        return failure;
    }
    if failure is string {
        return rejectOrder(req, failure);
    }

    log:printInfo("Order confirmed", orderId = req.orderId, restaurantId = req.restaurantId);
    publishOrderStatus(req.orderId, req.restaurantId, "CONFIRMED");
    warnIfLowStock(req);
}

function rejectOrder(OrderRequest req, string reason) returns error? {
    check saveRejectedOrder(req, reason);
    log:printWarn("Order rejected", orderId = req.orderId, reason = reason);
    publishOrderStatus(req.orderId, req.restaurantId, "REJECTED", reason);
}

// After taking stock, tell Notification about any item that is now low.
function warnIfLowStock(OrderRequest req) {
    foreach OrderLine line in req.lines {
        MenuItem|sql:Error item = getMenuItem(req.restaurantId, line.menuItemId);
        if item is MenuItem && item.stockQuantity <= lowStockThreshold {
            publishLowStock(item);
        }
    }
}

function handleOrderStatusChanged(json payload) returns error? {
    json orderIdJson = check payload.orderId;
    json statusJson = check payload.status;
    string orderId = orderIdJson.toString();
    // only a cancellation matters to us, the other statuses are driven by our own events
    if statusJson.toString().toUpperAscii() != "CANCELLED" {
        return;
    }
    boolean restocked = check cancelOrderAndRestock(orderId);
    if restocked {
        log:printInfo("Order cancelled, stock returned", orderId = orderId);
    } else {
        log:printInfo("Cancel ignored (unknown or already closed order)", orderId = orderId);
    }
}
