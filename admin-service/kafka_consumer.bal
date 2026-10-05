import ballerina/lang.value;
import ballerina/log;
import ballerinax/kafka;

// Listens to every business topic on the platform and keeps the reporting tables up to date.
// Own consumer group, so we get our own copy of each event and never take one away from
// the service that actually has to act on it.

listener kafka:Listener platformEventsListener = new (kafkaBootstrap, {
    groupId: consumerGroupId,
    topics: [
        customerRegisteredTopic,
        orderCreatedTopic,
        orderStatusTopic,
        restaurantOrderTopic,
        lowStockTopic,
        paymentCompletedTopic,
        paymentFailedTopic,
        driverAssignedTopic,
        deliveryStatusTopic
    ],
    // earliest: a fresh admin_db rebuilds the full history instead of starting from "now"
    offsetReset: kafka:OFFSET_RESET_EARLIEST,
    autoCommit: true
});

service on platformEventsListener {

    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) returns error? {
        foreach kafka:BytesConsumerRecord rec in records {
            string topic = rec.offset.partition.topic;
            // catch per record so one bad message can't block the partition
            do {
                string body = check string:fromBytes(rec.value);
                json payload = check value:fromJsonString(body);
                map<json> evt = check payload.ensureType();
                // unique per Kafka record, used to de-duplicate the low-stock log. The timestamp is
                // in there because offsets start again at 0 when the broker is recreated.
                string eventKey = string `${topic}-${rec.offset.partition.partition}-${rec.offset.offset}-${rec.timestamp}`;
                decimal at = <decimal>rec.timestamp / 1000d;
                check handleEvent(topic, evt, eventKey, at);
            } on fail error e {
                log:printError("Failed to process Kafka record", e, topic = topic);
            }
        }
    }
}

function handleEvent(string topic, map<json> evt, string eventKey, decimal at) returns error? {
    if topic == orderCreatedTopic {
        check applyOrderCreated(check requireText(evt, "orderId"), intOf(evt, "customerId"),
                intOf(evt, "restaurantId"), decimalOf(evt, "totalAmount"), at);
    } else if topic == orderStatusTopic {
        check applyOrderStatus(check requireText(evt, "orderId"), (check requireText(evt, "status")).toUpperAscii(), at);
    } else if topic == paymentCompletedTopic {
        check applyPayment(check requireText(evt, "orderId"), "PAID", at);
    } else if topic == paymentFailedTopic {
        check applyPayment(check requireText(evt, "orderId"), "FAILED", at);
    } else if topic == restaurantOrderTopic {
        check handleRestaurantDecision(evt, at);
    } else if topic == customerRegisteredTopic {
        check handleCustomerRegistered(evt, at);
    } else if topic == driverAssignedTopic {
        check applyDeliveryAssigned(check requireText(evt, "orderId"), intOf(evt, "driverId"),
                textOf(evt, "driverName"), at);
    } else if topic == deliveryStatusTopic {
        check applyDeliveryStatus(check requireText(evt, "orderId"),
                (check requireText(evt, "status")).toUpperAscii(), intOf(evt, "driverId"), at);
    } else if topic == lowStockTopic {
        check handleLowStock(evt, eventKey, at);
    }
}

function handleRestaurantDecision(map<json> evt, decimal at) returns error? {
    string status = (check requireText(evt, "status")).toUpperAscii();
    // CONFIRMED / PREPARING / READY come back to us as orders.status.changed, nothing to add here
    if status != "REJECTED" {
        return;
    }
    string reason = textOf(evt, "reason") ?: "Rejected by the restaurant";
    check applyRestaurantDecision(check requireText(evt, "orderId"), intOf(evt, "restaurantId"), reason, at);
}

function handleCustomerRegistered(map<json> evt, decimal at) returns error? {
    int? customerId = intOf(evt, "customerId");
    if customerId is () {
        return error("customers.registered without a customerId");
    }
    check applyCustomerRegistered(customerId, textOf(evt, "fullName") ?: "", textOf(evt, "email") ?: "", at);
}


function handleLowStock(map<json> evt, string eventKey, decimal at) returns error? {
    int? restaurantId = intOf(evt, "restaurantId");
    int? menuItemId = intOf(evt, "menuItemId");
    if restaurantId is () || menuItemId is () {
        return error("restaurants.stock.low without restaurantId/menuItemId");
    }
    check recordLowStock(eventKey, restaurantId, menuItemId, textOf(evt, "itemName") ?: "",
            intOf(evt, "stockQuantity") ?: 0, at);
}

// Loose field readers.
// Reports must not stop working because one team sends restaurantId as "3" and another as 3,
// or because somebody adds a field. So instead of binding to strict records we pick out the
// few fields we need and accept both spellings of a number.

function textOf(map<json> evt, string 'field) returns string? {
    json v = evt['field];
    if v is string {
        return v.trim().length() == 0 ? () : v;
    }
    if v is int {
        return v.toString();
    }
    return ();
}


function requireText(map<json> evt, string 'field) returns string|error {
    string? v = textOf(evt, 'field);
    if v is () {
        return error(string `event is missing '${'field}'`);
    }
    return v;
}

function intOf(map<json> evt, string 'field) returns int? {
    json v = evt['field];
    if v is int {
        return v;
    }
    if v is string {
        int|error parsed = int:fromString(v.trim());
        return parsed is int ? parsed : ();
    }
    return ();
}

function decimalOf(map<json> evt, string 'field) returns decimal? {
    json v = evt['field];
    if v is int|float|decimal {
        return <decimal>v;
    }
    if v is string {
        decimal|error parsed = decimal:fromString(v.trim());
        return parsed is decimal ? parsed : ();
    }
    return ();
}
