import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/sql;

// Takes a drafted notification, works out where it should go, stores it and sends it.

final http:Client customerClient = check new (customerServiceUrl, timeout = 5);

// Returns the id of the stored notification, or () if this exact one was already sent.
function notify(Draft draft) returns int?|error {
    string channel = CHANNEL_IN_APP;
    string? destination = ();

    string? phone = draft.phone;
    if phone is string {
        // the event told us the number (that's the case for drivers), a text reaches them fastest
        channel = CHANNEL_SMS;
        destination = phone;
    } else if draft.recipientType == CUSTOMER {
        Contact? contact = findContact(draft.recipientId);
        if contact is Contact {
            channel = CHANNEL_EMAIL;
            destination = contact.email;
        }
        // no contact details: it still lands in their in-app inbox
    }

    // Store first, send second. If we sent first and then crashed, the redelivered Kafka
    // message would send it again; this way the dedupe key stops the repeat.
    int? id = check insertNotification(draft, channel, destination);
    if id is () {
        log:printInfo("Duplicate notification skipped", dedupeKey = draft.dedupeKey);
        return ();
    }
    deliver(channel, destination, draft);
    return id;
}

// There is no mail server or SMS gateway in this setup, so "sending" is a log line.
// This is the only function that would change if a real provider was plugged in.
function deliver(string channel, string? destination, Draft draft) {
    log:printInfo(string `[${channel}] ${draft.title}: ${draft.message}`,
        to = destination ?: string `${draft.recipientType} ${draft.recipientId}`,
        eventType = draft.eventType, orderId = draft.orderId);
}

// Normally we already know the customer from customers.registered. If not (they signed up
// before this service existed, or the event got lost) we ask the Customer Service once
// and remember the answer. Never fails: without contact details we just fall back to in-app.
function findContact(int customerId) returns Contact? {
    Contact|sql:Error known = getContact(customerId);
    if known is Contact {
        return known;
    }
    if !(known is sql:NoRowsError) {
        log:printError("Contact lookup failed", known, customerId = customerId);
        return ();
    }
    Contact|error fetched = fetchContact(customerId);
    if fetched is error {
        log:printWarn("No contact details for customer", customerId = customerId, reason = fetched.message());
        return ();
    }
    error? saved = upsertContact(fetched);
    if saved is error {
        log:printError("Could not cache contact", saved, customerId = customerId);
    }
    return fetched;
}

function fetchContact(int customerId) returns Contact|error {
    http:Response res = check customerClient->get(string `/customers/${customerId}`);
    if res.statusCode != 200 {
        return error(string `customer-service returned ${res.statusCode}`);
    }
    json body = check res.getJsonPayload();
    CustomerView c = check body.cloneWithType();
    return {customerId: c.id, fullName: c.fullName, email: c.email, phone: c.phone};
}

// Who placed this order? Delivery events tell us directly (the hint), for everything else
// we look it up in what we stored from orders.created.
function customerForOrder(string orderId, int? hint = ()) returns int?|error {
    if hint is int {
        return hint;
    }
    // Topics aren't ordered against each other, so a status change can overtake its own
    // orders.created by a few milliseconds. Give it a moment before giving up.
    int attempt = 0;
    while attempt < 3 {
        OrderRef|sql:Error found = getOrderRef(orderId);
        if found is OrderRef {
            return found.customerId;
        }
        if !(found is sql:NoRowsError) {
            return found;
        }
        attempt += 1;
        runtime:sleep(0.5);
    }
    return ();
}
