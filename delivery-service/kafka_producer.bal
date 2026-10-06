import ballerina/log;
import ballerinax/kafka;

// Publishes the deliveries.* events.
// acks=all + retries so a broker-accepted event isn't lost. Everything is keyed by orderId
// so all events of one order stay in one partition and arrive in the order we sent them.

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, {
    clientId: "delivery-service-producer",
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

// Best effort on purpose: the change is already saved in MySQL, a Kafka hiccup
// should cost us a notification, not the delivery itself.
function send(string topic, string orderId, string payload) {
    error? result = kafkaProducer->send({
        topic,
        key: orderId.toBytes(),
        value: payload.toBytes()
    });
    if result is error {
        log:printError("Failed to publish " + topic, result, orderId = orderId);
    } else {
        log:printInfo("Published " + topic, orderId = orderId);
    }
}

// For the Notification Service: tell the customer who is coming.
function publishDriverAssigned(Delivery delivery, Driver driver) {
    DriverAssignedEvent evt = {
        eventType: "DRIVER_ASSIGNED",
        orderId: delivery.orderId,
        customerId: delivery.customerId,
        restaurantId: delivery.restaurantId,
        driverId: driver.id,
        driverName: driver.fullName,
        driverPhone: driver.phone,
        vehicle: driver.vehicle,
        plateNumber: driver.plateNumber,
        occurredAt: nowIso()
    };
    send(driverAssignedTopic, delivery.orderId, evt.toJsonString());
}

// The Order Service moves the order on OUT_FOR_DELIVERY and DELIVERED from this topic,
// so those two status strings have to stay exactly as they are.
function publishDeliveryStatus(Delivery delivery) {
    DeliveryStatusEvent evt = {
        eventType: "DELIVERY_" + delivery.status,
        orderId: delivery.orderId,
        status: delivery.status,
        customerId: delivery.customerId,
        driverId: delivery.driverId,
        occurredAt: nowIso()
    };
    send(deliveryStatusTopic, delivery.orderId, evt.toJsonString());
}

// One event per GPS ping while the driver is on a job (live map on the customer side).
function publishDriverLocation(string orderId, int driverId, LocationUpdate loc) {
    DriverLocationEvent evt = {
        eventType: "DRIVER_LOCATION",
        orderId,
        driverId,
        latitude: loc.latitude,
        longitude: loc.longitude,
        occurredAt: nowIso()
    };
    send(driverLocationTopic, orderId, evt.toJsonString());
}
