// The wording of every notification, kept in one place so it can be changed
// without touching the Kafka or database code. Each function returns [title, message].

// Order ids are UUIDs, nobody wants to read 36 characters in a text message
function shortId(string orderId) returns string {
    return "#" + (orderId.length() > 8 ? orderId.substring(0, 8) : orderId);
}

function welcomeText(string fullName) returns [string, string] {
    return ["Welcome!", string `Hi ${fullName}, your account is ready. Hungry? Have a look at what's open near you.`];
}

function orderPlacedText(string orderId, decimal total) returns [string, string] {
    return [
        "Order received",
        string `We got your order ${shortId(orderId)} for N$ ${total}. We'll let you know when the restaurant confirms it.`
    ];
}

// () for statuses that don't deserve a message of their own
// (CREATED is covered by "Order received", anything unknown we'd rather skip than guess).
function orderStatusText(string orderId, string status) returns [string, string]? {
    string tag = shortId(orderId);
    match status {
        "CONFIRMED" => {
            return ["Order confirmed", string `The restaurant accepted your order ${tag}.`];
        }
        "PREPARING" => {
            return ["Being prepared", string `The kitchen has started on your order ${tag}.`];
        }
        "READY" => {
            return ["Order ready", string `Your order ${tag} is ready and waiting for a driver.`];
        }
        "OUT_FOR_DELIVERY" => {
            return ["On its way", string `Your order ${tag} has left the restaurant and is on its way to you.`];
        }
        "DELIVERED" => {
            return ["Delivered", string `Your order ${tag} has been delivered. Enjoy your meal!`];
        }
        "CANCELLED" => {
            return ["Order cancelled", string `Your order ${tag} was cancelled.`];
        }
    }
    return ();
}

function paymentCompletedText(string orderId) returns [string, string] {
    return ["Payment received", string `Your payment for order ${shortId(orderId)} went through.`];
}

function paymentFailedText(string orderId) returns [string, string] {
    return [
        "Payment failed",
        string `We could not take payment for order ${shortId(orderId)}, so it has been cancelled. You have not been charged.`
    ];
}

function driverAssignedText(string orderId, string driverName, string driverPhone, string? vehicle)
        returns [string, string] {
    string ride = vehicle is string && vehicle.trim().length() > 0 ? string ` (${vehicle})` : "";
    return [
        "Driver assigned",
        string `${driverName}${ride} is collecting your order ${shortId(orderId)}. You can reach them on ${driverPhone}.`
    ];
}

// goes to the driver, not the customer
function newJobText(string orderId) returns [string, string] {
    return ["New delivery", string `You have a new delivery: order ${shortId(orderId)}. Head to the restaurant to pick it up.`];
}

function jobCancelledText(string orderId) returns [string, string] {
    return ["Delivery cancelled", string `Order ${shortId(orderId)} was cancelled, no need to pick it up.`];
}

// goes to the restaurant
function lowStockText(string itemName, int left) returns [string, string] {
    if left <= 0 {
        return ["Sold out", string `${itemName} is sold out. Restock it or take it off the menu.`];
    }
    return ["Stock running low", string `Only ${left} left of ${itemName}.`];
}
