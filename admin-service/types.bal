// Shapes of the report responses. The Kafka events are read loosely (see kafka_consumer.bal),
// so there are no event records in here.

// GET /admin/reports/summary
public type SummaryReport record {|
    int totalOrders;
    int activeOrders;
    int deliveredOrders;
    int cancelledOrders;
    int paidOrders;
    decimal grossRevenue;           // paid orders that were not cancelled
    decimal averageOrderValue;
    decimal? averageDeliveryMinutes; // order placed -> delivered, null until something was delivered
    int customers;
    int deliveriesCompleted;
    string generatedAt;
|};

type OrderTotalsRow record {|
    int totalOrders;
    int activeOrders;
    int deliveredOrders;
    int cancelledOrders;
    int paidOrders;
    decimal grossRevenue;
    decimal? averageDeliveryMinutes;
|};

// GET /admin/reports/orders/status
public type StatusCount record {|
    string status;
    int orders;
    decimal totalAmount;
|};

// GET /admin/reports/revenue/daily
public type DailyRevenue record {|
    string orderDate;
    int orders;
    int cancelled;
    decimal revenue;
|};

// GET /admin/reports/restaurants
public type RestaurantReport record {|
    int restaurantId;
    int orders;
    int delivered;
    int cancelled;
    decimal revenue;
|};

// GET /admin/reports/customers
public type CustomerReport record {|
    int customerId;
    string? fullName;   // null when the customer registered before we started listening
    string? email;
    int orders;
    decimal spent;
|};

// GET /admin/reports/drivers
public type DriverReport record {|
    int driverId;
    string? driverName;
    int assigned;
    int delivered;
    decimal? averageMinutes;   // assigned -> delivered
|};

// GET /admin/reports/deliveries
public type DeliveryStatusCount record {|
    string status;
    int deliveries;
|};

// GET /admin/reports/stock
public type LowStockEntry record {|
    int restaurantId;
    int menuItemId;
    string itemName;
    int stockQuantity;
    string occurredAt;
|};

// GET /admin/orders
public type OrderRow record {|
    string orderId;
    int? customerId;
    int? restaurantId;
    decimal? totalAmount;
    string status;
    string paymentStatus;
    string? rejectReason;
    string createdAt;
    string updatedAt;
    string? deliveredAt;
|};

// GET /admin/services
public type ServiceHealth record {|
    string name;
    string url;
    string status;      // UP | DOWN
    int? httpStatus;
    int latencyMs;
    string? detail;
|};

public type ErrorBody record {|
    string code;
    string message;
|};
