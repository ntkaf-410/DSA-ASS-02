import ballerina/log;
import ballerina/time;
import ballerinax/kafka;


// kafka_producer.bal - publishes customers.registered.
// acks=all + retries => no event is silently lost once the broker accepts it.
// Keyed by customerId so all events for one customer land in one partition
// (preserves per-customer ordering).

final kafka:Producer kafkaProducer = check new (kafkaBootstrap, {
    clientId: "customer-service-producer",
    acks: kafka:ACKS_ALL,
    retryCount: 3
});

# Best-effort publish: a Kafka outage must NOT block customer registration,
# so failures are logged instead of propagated.
function publishCustomerRegistered(Customer c) {
    CustomerRegisteredEvent evt = {
        eventType: "CUSTOMER_REGISTERED",
        customerId: c.id,
        fullName: c.fullName,
        email: c.email,
        phone: c.phone,
        occurredAt: time:utcToString(time:utcNow())
    };
    error? result = kafkaProducer->send({
        topic: customerRegisteredTopic,
        key: c.id.toString().toBytes(),
        value: evt.toJsonString().toBytes()
    });
    if result is error {
        log:printError("Failed to publish customers.registered", result, customerId = c.id);
    } else {
        log:printInfo("Published customers.registered", customerId = c.id);
    }
}
