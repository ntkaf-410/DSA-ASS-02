import ballerina/lang.value;
import ballerina/log;
import ballerinax/kafka;

// Listens to what the other services publish and turns it into notifications.
// Our own consumer group, so we get every message without taking it away from anyone.

listener kafka:Listener eventsListener = new (kafkaBootstrap, {
    groupId: consumerGroupId,
    topics: [
        customerRegisteredTopic,
        orderCreatedTopic,
        orderStatusTopic,
        paymentCompletedTopic,
        paymentFailedTopic,
        lowStockTopic,
        driverAssignedTopic,
        deliveryStatusTopic
    ],
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: true
});

service on eventsListener {

    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            string topic = rec.offset.partition.topic;
            // catch per record so one bad message can't block the partition
            do {
                string body = check string:fromBytes(rec.value);
                json payload = check value:fromJsonString(body);
                check dispatch(topic, payload);
            } on fail error e {
                log:printError("Failed to process Kafka record", e, topic = topic);
            }
        }
    }
}

function dispatch(string topic, json payload) returns error? {
    if topic == customerRegisteredTopic {
        check handleCustomerRegistered(payload);
    } else if topic == orderCreatedTopic {
        check handleOrderCreated(payload);
    } else if topic == orderStatusTopic {
        check handleOrderStatusChanged(payload);
    } else if topic == paymentCompletedTopic {
        check handlePayment(payload, true);
    } else if topic == paymentFailedTopic {
        check handlePayment(payload, false);
    } else if topic == lowStockTopic {
        check handleLowStock(payload);
    } else if topic == driverAssignedTopic {
        check handleDriverAssigned(payload);
    } else if topic == deliveryStatusTopic {
        check handleDeliveryStatus(payload);
    }
}

// New customer: remember how to reach them, then say hello.
function handleCustomerRegistered(json payload) returns error? {
    CustomerRegisteredEvent evt = check payload.cloneWithType();
    check upsertContact({
        customerId: evt.customerId,
        fullName: evt.fullName,
        email: evt.email,
        phone: evt.phone
    });
    [string, string] text = welcomeText(evt.fullName);
    _ = check notify({
        recipientType: CUSTOMER,
        recipientId: evt.customerId,
        eventType: "CUSTOMER_WELCOME",
        title: text[0],
        message: text[1],
        dedupeKey: string `customer:${evt.customerId}:WELCOME`
    });
}

function handleOrderCreated(json payload) returns error? {
    OrderCreatedEvent evt = check payload.cloneWithType();
    // keep the order -> customer link, later events for this order only carry the orderId
    check saveOrderRef({orderId: evt.orderId, customerId: evt.customerId, restaurantId: evt.restaurantId});
    [string, string] text = orderPlacedText(evt.orderId, evt.totalAmount);
    _ = check notify({
        recipientType: CUSTOMER,
        recipientId: evt.customerId,
        orderId: evt.orderId,
        eventType: "ORDER_CREATED",
        title: text[0],
        message: text[1],
        dedupeKey: string `${evt.orderId}:ORDER_CREATED`
    });
}

function handleOrderStatusChanged(json payload) returns error? {
    OrderStatusEvent evt = check payload.cloneWithType();
    check notifyOrderStatus(evt.orderId, evt.status.trim().toUpperAscii(), ());
}

// Shared by orders.status.changed and deliveries.status.changed. OUT_FOR_DELIVERY and DELIVERED
// show up on both (the Order Service repeats what the Delivery Service said), and because both
// paths build the same dedupe key the customer is only told once.
function notifyOrderStatus(string orderId, string status, int? customerHint) returns error? {
    [string, string]? text = orderStatusText(orderId, status);
    if text is () {
        return;
    }
    int? customerId = check customerForOrder(orderId, customerHint);
    if customerId is () {
        log:printWarn("Status change for an order we don't know, nobody to notify",
            orderId = orderId, status = status);
        return;
    }
    _ = check notify({
        recipientType: CUSTOMER,
        recipientId: customerId,
        orderId,
        eventType: "ORDER_" + status,
        title: text[0],
        message: text[1],
        dedupeKey: string `${orderId}:ORDER_${status}`
    });
}

function handlePayment(json payload, boolean completed) returns error? {
    PaymentEvent evt = check payload.cloneWithType();
    int? customerId = check customerForOrder(evt.orderId);
    if customerId is () {
        log:printWarn("Payment result for an order we don't know, nobody to notify", orderId = evt.orderId);
        return;
    }
    [string, string] text = completed ? paymentCompletedText(evt.orderId) : paymentFailedText(evt.orderId);
    string eventType = completed ? "PAYMENT_COMPLETED" : "PAYMENT_FAILED";
    _ = check notify({
        recipientType: CUSTOMER,
        recipientId: customerId,
        orderId: evt.orderId,
        eventType,
        title: text[0],
        message: text[1],
        dedupeKey: string `${evt.orderId}:${eventType}`
    });
}

// This one is for the restaurant, not a customer. There's no restaurant contact list here,
// so it lands in the restaurant's in-app inbox (GET /notifications?recipientType=RESTAURANT&recipientId=..).
function handleLowStock(json payload) returns error? {
    LowStockEvent evt = check payload.cloneWithType();
    [string, string] text = lowStockText(evt.itemName, evt.stockQuantity);
    // the stock level is part of the key: "5 left" and later "2 left" are two different warnings,
    // the same "5 left" delivered twice is not
    _ = check notify({
        recipientType: RESTAURANT,
        recipientId: evt.restaurantId,
        eventType: "STOCK_LOW",
        title: text[0],
        message: text[1],
        dedupeKey: string `stock:${evt.menuItemId}:${evt.stockQuantity}:${evt?.occurredAt ?: ""}`
    });
}

// Two people need to hear about this: the customer (who is coming) and the driver (new job).
function handleDriverAssigned(json payload) returns error? {
    DriverAssignedEvent evt = check payload.cloneWithType();

    [string, string] job = newJobText(evt.orderId);
    _ = check notify({
        recipientType: DRIVER,
        recipientId: evt.driverId,
        orderId: evt.orderId,
        eventType: "DELIVERY_JOB",
        title: job[0],
        message: job[1],
        phone: evt.driverPhone,
        dedupeKey: string `${evt.orderId}:DELIVERY_JOB:${evt.driverId}`
    });

    int? customerId = check customerForOrder(evt.orderId, evt?.customerId);
    if customerId is () {
        log:printWarn("Driver assigned for an order we don't know, customer not notified", orderId = evt.orderId);
        return;
    }
    [string, string] text = driverAssignedText(evt.orderId, evt.driverName, evt.driverPhone, evt?.vehicle);
    _ = check notify({
        recipientType: CUSTOMER,
        recipientId: customerId,
        orderId: evt.orderId,
        eventType: "DRIVER_ASSIGNED",
        title: text[0],
        message: text[1],
        dedupeKey: string `${evt.orderId}:DRIVER_ASSIGNED`
    });
}

function handleDeliveryStatus(json payload) returns error? {
    DeliveryStatusEvent evt = check payload.cloneWithType();
    string status = evt.status.trim().toUpperAscii();
    if status == "CANCELLED" {
        // The customer hears about the cancel from orders.status.changed.
        // This event exists for the driver who was already on the way.
        int? driverId = evt?.driverId;
        if driverId is int {
            [string, string] text = jobCancelledText(evt.orderId);
            _ = check notify({
                recipientType: DRIVER,
                recipientId: driverId,
                orderId: evt.orderId,
                eventType: "DELIVERY_CANCELLED",
                title: text[0],
                message: text[1],
                dedupeKey: string `${evt.orderId}:DELIVERY_CANCELLED:${driverId}`
            });
        }
        return;
    }
    if status == "OUT_FOR_DELIVERY" || status == "DELIVERED" {
        check notifyOrderStatus(evt.orderId, status, evt?.customerId);
    }
}
