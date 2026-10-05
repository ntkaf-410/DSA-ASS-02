public type OrderItem record {|
    int menuItemId;
    string name;
    int quantity;
    decimal unitPrice;
|};

public type OrderCreatedEvent record {|
    string orderId;
    int customerId;
    int restaurantId;
    decimal totalAmount;
    int deliveryAddressId;
    OrderItem[] items;
|};

public type PaymentEvent record {|
    string orderId;
|};

public type PaymentRecord record {|
    string orderId;
    int customerId;
    decimal amount;
    string currency;
    string status;
    string? failureReason;
    string createdAt;
    string updatedAt;
|};

type PaymentRow record {|
    string orderId;
    int customerId;
    decimal amount;
    string currency;
    string status;
    string? failureReason;
    string createdAt;
    string updatedAt;
|};
