import ballerina/lang.value;
import ballerina/log;
import ballerina/sql;
import ballerinax/kafka;

// Consumes orders.created (open a delivery) and orders.status.changed
// (READY -> find a driver, CANCELLED -> call it off).
// Our own consumer group, so every other service still gets its own copy of each message.

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

// We don't need a driver yet, the kitchen hasn't even started. We just note who the order
// belongs to, because the READY event later only carries the orderId.
function handleOrderCreated(json payload) returns error? {
    OrderCreatedEvent evt = check payload.cloneWithType();
    if evt.orderId.trim().length() == 0 {
        return error("orders.created has an empty orderId");
    }
    DeliveryRequest req = {
        orderId: evt.orderId,
        customerId: evt.customerId,
        restaurantId: evt.restaurantId
    };
    int? addressId = evt?.deliveryAddressId;
    if addressId is int {
        req.deliveryAddressId = addressId;
    }
    check insertPendingDelivery(req);
    log:printInfo("Delivery opened", orderId = evt.orderId, customerId = evt.customerId);
}

function handleOrderStatusChanged(json payload) returns error? {
    OrderStatusEvent evt = check payload.cloneWithType();
    string status = evt.status.trim().toUpperAscii();
    if status == "READY" {
        Delivery delivery = check requestDelivery(evt.orderId);
        log:printInfo("Order ready for pickup", orderId = evt.orderId, deliveryStatus = delivery.status);
    } else if status == CANCELLED {
        check handleOrderCancelled(evt.orderId);
    }
    // Everything else is either kitchen business (CONFIRMED, PREPARING) or our own
    // OUT_FOR_DELIVERY / DELIVERED coming back round through the Order Service.
}

function handleOrderCancelled(string orderId) returns error? {
    Delivery|sql:Error before = getDelivery(orderId);
    if before is sql:NoRowsError {
        log:printInfo("Cancel for an order we never saw, ignored", orderId = orderId);
        return;
    }
    if before is sql:Error {
        return before;
    }
    boolean cancelled = check cancelDelivery(orderId);
    if !cancelled {
        log:printInfo("Cancel ignored (already on the road or closed)", orderId = orderId, status = before.status);
        return;
    }
    log:printInfo("Delivery cancelled", orderId = orderId);
    if before.driverId is int {
        // A driver was already heading to the restaurant: let them know it's off,
        // and since they're free again see if another order is waiting.
        publishDeliveryStatus(check getDelivery(orderId));
        assignWaitingDeliveries();
    }
}
