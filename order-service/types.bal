public enum OrderStatus {
    CREATED,
    CONFIRMED,
    PREPARING,
    READY,
    OUT_FOR_DELIVERY,
    DELIVERED,
    CANCELLED
}

public type OrderItem record {|
    int menuItemId;
    string name;
    int quantity;
    decimal unitPrice;
|};

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
    string paymentStatus;
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

public type OrderCreatedEvent record {|
    string orderId;
    int customerId;
    int restaurantId;
    decimal totalAmount;
    int deliveryAddressId;
    OrderItem[] items;
|};

public type OrderStatusEvent record {|
    string orderId;
    string status;
|};

public type PaymentEvent record {
    string orderId;
};

public type RestaurantOrderEvent record {
    string orderId;
    string status;
    string? reason?;
};

public type DeliveryEvent record {
    string orderId;
    string status; 
};

// ---------- domain errors ----------
public type OrderNotFound distinct error;
public type InvalidTransition distinct error;
public type ConflictError distinct error;
