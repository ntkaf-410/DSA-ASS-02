// API payloads, DB row shapes and Kafka event contracts.

// Who a notification is for
const CUSTOMER = "CUSTOMER";
const DRIVER = "DRIVER";
const RESTAURANT = "RESTAURANT";

// How it went out
const CHANNEL_EMAIL = "EMAIL";
const CHANNEL_SMS = "SMS";
const CHANNEL_IN_APP = "IN_APP";

public type Notification record {|
    int id;
    string recipientType;
    int recipientId;
    string? orderId;
    string eventType;       // ORDER_CONFIRMED, PAYMENT_FAILED, DRIVER_ASSIGNED, ...
    string channel;
    string? destination;    // the e-mail address or phone number it went to, null for in-app
    string title;
    string message;
    string status;
    boolean isRead;
    string createdAt;
|};

// POST /notifications, for the Admin Service or anyone who wants to send a custom message
public type ManualNotification record {|
    string recipientType;
    int recipientId;
    string title;
    string message;
    string orderId?;
|};

public type UnreadCount record {|
    int customerId;
    int unread;
|};

// What the consumers hand to the notifier. dedupeKey is what makes a redelivered
// Kafka message harmless: same key, no second notification.
type Draft record {|
    string recipientType;
    int recipientId;
    string eventType;
    string title;
    string message;
    string? orderId = ();
    string? phone = ();      // set when the event itself told us the number (drivers)
    string? dedupeKey = ();
|};

// Contact details we keep per customer so we know where to send things
type Contact record {|
    int customerId;
    string fullName;
    string email;
    string phone;
|};

// orderId -> customer. Most events only carry the orderId.
type OrderRef record {|
    string orderId;
    int customerId;
    int restaurantId;
|};

// Kafka events we consume. All open records: we only name the fields we use,
// so a producer adding a field can't break us.
type CustomerRegisteredEvent record {
    int customerId;
    string fullName;
    string email;
    string phone;
};

type OrderCreatedEvent record {
    string orderId;
    int customerId;
    int restaurantId;
    decimal totalAmount;
};

type OrderStatusEvent record {
    string orderId;
    string status;
};

type PaymentEvent record {
    string orderId;
};

type LowStockEvent record {
    int restaurantId;
    int menuItemId;
    string itemName;
    int stockQuantity;
    string occurredAt?;
};

type DriverAssignedEvent record {
    string orderId;
    int? customerId?;
    int driverId;
    string driverName;
    string driverPhone;
    string? vehicle?;
    string? plateNumber?;
};

type DeliveryStatusEvent record {
    string orderId;
    string status;
    int? customerId?;
    int? driverId?;
};

// The bit of GET /customers/{id} we care about
type CustomerView record {
    int id;
    string fullName;
    string email;
    string phone;
};

public type ErrorBody record {|
    string code;
    string message;
|};
