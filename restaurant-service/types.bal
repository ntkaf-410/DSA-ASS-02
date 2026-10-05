// API payloads, DB row shapes and Kafka event contracts.

// Restaurants
public type RestaurantInput record {|
    string name;
    string description?;
    string cuisine;
    string phone;
    string address;
    string city;
    decimal latitude?;
    decimal longitude?;
    boolean isActive?;   // only used on update
|};

public type Restaurant record {|
    int id;
    string name;
    string? description;
    string cuisine;
    string phone;
    string address;
    string city;
    decimal? latitude;
    decimal? longitude;
    boolean isActive;
    string createdAt;
|};

// What the Order Service checks before accepting an order
public type RestaurantStatus record {|
    int restaurantId;
    boolean isActive;
    boolean isOpen;
    boolean acceptingOrders;
|};

// Opening hours. dayOfWeek: 0 = Sunday ... 6 = Saturday. Times are "HH:MM" (24h).
public type OpeningHoursInput record {|
    int dayOfWeek;
    boolean isClosed?;
    string openTime?;
    string closeTime?;
|};

public type OpeningHours record {|
    int dayOfWeek;
    boolean isClosed;
    string? openTime;
    string? closeTime;
|};

// Menu and inventory (stock lives on the menu item)
public type MenuItemInput record {|
    string name;
    string description?;
    string category;
    decimal price;
    int stockQuantity?;
    boolean isAvailable?;
|};

public type MenuItem record {|
    int id;
    int restaurantId;
    string name;
    string? description;
    string category;
    decimal price;
    boolean isAvailable;
    int stockQuantity;
    string createdAt;
|};

public type StockUpdate record {|
    int stockQuantity;
|};

// Kitchen side of an order (what the restaurant sees)
public type StatusUpdate record {|
    string status;
|};

public type KitchenOrder record {|
    string orderId;
    int restaurantId;
    int? customerId;
    string status;
    string? rejectReason;
    json items;
    string createdAt;
    string updatedAt;
|};

type KitchenOrderRow record {|
    string orderId;
    int restaurantId;
    int? customerId;
    string status;
    string? rejectReason;
    string? itemsJson;
    string createdAt;
    string updatedAt;
|};

// Parsed orders.created event
type OrderLine record {|
    int menuItemId;
    int quantity;
|};

type OrderRequest record {|
    string orderId;
    int? customerId;
    int restaurantId;
    OrderLine[] lines;
|};

// Kafka events we produce
// Goes to `restaurants.order.status`. status = CONFIRMED | REJECTED | PREPARING | READY
public type RestaurantOrderEvent record {|
    string eventType;
    string orderId;
    int restaurantId;
    string status;
    string? reason;
    string occurredAt;
|};

// Goes to `restaurants.stock.low`
public type LowStockEvent record {|
    string eventType;
    int restaurantId;
    int menuItemId;
    string itemName;
    int stockQuantity;
    string occurredAt;
|};

public type ErrorBody record {|
    string code;
    string message;
|};
