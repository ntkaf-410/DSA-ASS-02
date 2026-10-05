import ballerina/log;
import ballerinax/kafka;

listener kafka:Listener orderListener = new (kafkaBootstrap, {
    groupId: consumerGroup,
    topics: [topicPaymentCompleted, topicPaymentFailed, topicDeliveryStatus, topicRestaurantOrderStatus]
});

service kafka:Service on orderListener {
    remote function onConsumerRecord(kafka:BytesConsumerRecord[] records) {
        foreach kafka:BytesConsumerRecord rec in records {
            error? r = handleRecord(rec);
            if r is error {
                log:printError("failed to process record", r);
            }
        }
    }
}

function restaurantToOrderStatus(string s) returns string? {
    match s {
        "CONFIRMED" => {
            return CONFIRMED;
        }
        "REJECTED" => {
            return CANCELLED;
        }
        "PREPARING" => {
            return PREPARING;
        }
        "READY" => {
            return READY;
        }
    }
    return ();
}

function handleRecord(kafka:BytesConsumerRecord rec) returns error? {
    string topic = rec.offset.partition.topic;
    string body = check string:fromBytes(rec.value);
    json j = check body.fromJsonString();

    if topic == topicRestaurantOrderStatus {
        RestaurantOrderEvent ev = check j.fromJsonWithType();
        string? target = restaurantToOrderStatus(ev.status);
        if target is () {
            log:printWarn("ignoring unknown restaurant status", status = ev.status);
            return;
        }
        if ev.status == "REJECTED" {
            log:printInfo("restaurant rejected order", orderId = ev.orderId, reason = ev?.reason);
        }
        check applyIdempotent(ev.orderId, target, "restaurant-service");
    } else if topic == topicPaymentCompleted {
        PaymentEvent ev = check j.fromJsonWithType();
        check setPaymentStatus(ev.orderId, "PAID");
    } else if topic == topicPaymentFailed {
        PaymentEvent ev = check j.fromJsonWithType();
        check setPaymentStatus(ev.orderId, "FAILED");
        check applyIdempotent(ev.orderId, CANCELLED, "payment-service");
    } else if topic == topicDeliveryStatus {
        DeliveryEvent ev = check j.fromJsonWithType();
        if ev.status == OUT_FOR_DELIVERY || ev.status == DELIVERED {
            check applyIdempotent(ev.orderId, ev.status, "delivery-service");
        } else {
            log:printWarn("ignoring unknown delivery status", status = ev.status);
        }
    }
}

function applyIdempotent(string orderId, string next, string actor) returns error? {
    OrderRecord|error r = applyTransition(orderId, next, actor);
    if r is InvalidTransition {
        log:printWarn("event ignored (already applied or not allowed)", orderId = orderId, target = next);
        return;
    }
    if r is error {
        return r; 
    }
    log:printInfo("order updated from event", orderId = orderId, status = next, actor = actor);
}
