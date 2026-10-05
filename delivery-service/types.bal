// API payloads, DB row shapes and Kafka event contracts.

// Driver states. BUSY is only ever set by us when a delivery is attached,
// the driver app just toggles between the other two.
const DRIVER_OFFLINE = "OFFLINE";
const DRIVER_AVAILABLE = "AVAILABLE";
const DRIVER_BUSY = "BUSY";

// Delivery states, in the order they normally happen
const PENDING = "PENDING";                   // order placed, kitchen still busy
const AWAITING_DRIVER = "AWAITING_DRIVER";   // food is ready, nobody picked yet
const ASSIGNED = "ASSIGNED";                 // driver is heading to the restaurant
const OUT_FOR_DELIVERY = "OUT_FOR_DELIVERY"; // driver has the food
const DELIVERED = "DELIVERED";
const CANCELLED = "CANCELLED";

// Drivers
public type DriverInput record {|
    string fullName;
    string phone;
    string vehicle?;      // free text: "motorbike", "car", ...
    string plateNumber?;
|};

public type Driver record {|
    int id;
    string fullName;
    string phone;
    string? vehicle;
    string? plateNumber;
    string status;
    decimal? latitude;
    decimal? longitude;
    string? locationUpdatedAt;
    string? lastAssignedAt;
    string createdAt;
|};

public type DriverStatusUpdate record {|
    string status;   // AVAILABLE or OFFLINE
|};

public type LocationUpdate record {|
    decimal latitude;
    decimal longitude;
|};

// Deliveries (one per order, the orderId is the key everywhere)
public type DeliveryRequest record {|
    string orderId;
    int customerId?;
    int restaurantId?;
    int deliveryAddressId?;
|};

public type Delivery record {|
    string orderId;
    int? customerId;
    int? restaurantId;
    int? deliveryAddressId;
    int? driverId;
    string status;
    string? readyAt;
    string? assignedAt;
    string? pickedUpAt;
    string? deliveredAt;
    string createdAt;
    string updatedAt;
|};

// Leave driverId out to let the service pick one
public type AssignRequest record {|
    int driverId?;
|};

public type DeliveryStatusUpdate record {|
    string status;   // OUT_FOR_DELIVERY or DELIVERED
|};

// Tracking (what the customer app polls)
public type TrackingEvent record {|
    string status;
    string? note;
    string occurredAt;
|};

public type DriverSummary record {|
    int id;
    string fullName;
    string phone;
    string? vehicle;
    string? plateNumber;
    decimal? latitude;
    decimal? longitude;
    string? locationUpdatedAt;
|};

public type TrackingView record {|
    string orderId;
    string status;
    DriverSummary? driver;
    TrackingEvent[] timeline;
|};

type IdRow record {|
    int id;
|};

type OrderIdRow record {|
    string orderId;
|};

// Kafka events we consume. Open records on purpose: the Order Service sends more than
// we need (items, totals, ...) and we shouldn't break when it adds a field.
type OrderCreatedEvent record {
    string orderId;
    int customerId;
    int restaurantId;
    int deliveryAddressId?;
};

type OrderStatusEvent record {
    string orderId;
    string status;
};

// Kafka events we produce
// Goes to `deliveries.driver.assigned`. Carries the driver's contact details so the
// Notification Service doesn't have to call us back.
public type DriverAssignedEvent record {|
    string eventType;
    string orderId;
    int? customerId;
    int? restaurantId;
    int driverId;
    string driverName;
    string driverPhone;
    string? vehicle;
    string? plateNumber;
    string occurredAt;
|};

// Goes to `deliveries.status.changed`. status = OUT_FOR_DELIVERY | DELIVERED | CANCELLED.
// The Order Service only reads orderId + status and moves the order on the first two.
public type DeliveryStatusEvent record {|
    string eventType;
    string orderId;
    string status;
    int? customerId;
    int? driverId;
    string occurredAt;
|};

// Goes to `deliveries.location.updated`, one per GPS ping while a driver is on a job
public type DriverLocationEvent record {|
    string eventType;
    string orderId;
    int driverId;
    decimal latitude;
    decimal longitude;
    string occurredAt;
|};

public type ErrorBody record {|
    string code;
    string message;
|};

// domain errors
type AssignmentConflict distinct error;
type InvalidTransition distinct error;
