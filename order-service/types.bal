public enum OrderStatus {
    CREATED,
    CONFIRMED,
    PREPARING,
    READY,
    OUT_FOR_DELIVERY,
    DELIVERED,
    CANCELLED
}

// ---------- API records ----------
// Stored/returned item: name and price are copied from the Restaurant Service menu at order time.
public type OrderItem record {|
    int menuItemId;
    string name;
    int quantity;
    decimal unitPrice;
|};

// The client only sends WHICH items and HOW MANY; prices come from the menu, never from the client.
public type CreateOrderItem record {|
    int menuItemId;
    int quantity;
|};

public type CreateOrderRequest record {|
    int customerId;
    int restaurantId;
    int deliveryAddressId;
    CreateOrderItem[] items;
|};

public type StatusUpdateRequest record {|
    string status;
|};

public type OrderRecord record {|
    string orderId;
    int customerId;
    int restaurantId;
    int deliveryAddressId;
    decimal totalAmount;
    string status;
    string paymentStatus; // PENDING | PAID | FAILED
    OrderItem[] items;
    string createdAt;
    string updatedAt;
|};

public type StatusHistoryEntry record {|
    string? fromStatus;
    string toStatus;
    string changedBy;
    string changedAt;
|};

// ---------- DB row ----------
type OrderRow record {|
    string order_id;
    int customer_id;
    int restaurant_id;
    int delivery_address_id;
    decimal total_amount;
    string status;
    string payment_status;
    string created_at;
    string updated_at;
|};

// ---------- Kafka event contracts ----------
// Produced. Each item carries menuItemId + quantity (Restaurant Service) and name + unitPrice (Customer Service).
public type OrderCreatedEvent record {|
    string orderId;
    int customerId;
    int restaurantId;
    decimal totalAmount;
    int deliveryAddressId;
    OrderItem[] items;
|};

// Produced. Matches Customer Service's {orderId, status}.
public type OrderStatusEvent record {|
    string orderId;
    string status;
|};

// Consumed. Open records: extra fields from other services are ignored.
public type PaymentEvent record {
    string orderId;
};

// Person 2's RestaurantOrderEvent: status = CONFIRMED | REJECTED | PREPARING | READY
public type RestaurantOrderEvent record {
    string orderId;
    string status;
    string? reason?;
};

public type DeliveryEvent record {
    string orderId;
    string status; // OUT_FOR_DELIVERY | DELIVERED
};

// ---------- domain errors ----------
public type OrderNotFound distinct error;
public type InvalidTransition distinct error;
public type ConflictError distinct error;
