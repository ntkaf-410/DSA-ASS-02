
// types.bal - API payloads, DB row shapes and Kafka event contracts.


// Customers
public type CustomerRegistration record {|
    string fullName;
    string email;
    string phone;
    string password;
|};

public type CustomerUpdate record {|
    string fullName;
    string phone;
|};

public type LoginRequest record {|
    string email;
    string password;
|};

# Public customer profile (never contains the password hash).
public type Customer record {|
    int id;
    string fullName;
    string email;
    string phone;
    string createdAt;
|};

type CredentialRow record {|
    int id;
    string passwordHash;
|};

// Addresses
public type AddressInput record {|
    string label;          // e.g. "Home", "Work"
    string street;
    string city;
    string region?;
    string postalCode?;
    string country?;       // defaults to "Namibia"
    decimal latitude?;     // optional, used by driver-location bonus feature
    decimal longitude?;
    boolean isDefault?;    // only honoured on create; use /default endpoint afterwards
|};

public type Address record {|
    int id;
    int customerId;
    string label;
    string street;
    string city;
    string? region;
    string? postalCode;
    string country;
    decimal? latitude;
    decimal? longitude;
    boolean isDefault;
|};

// Order history (read model fed by Kafka) 
public type OrderSummary record {|
    string orderId;
    int customerId;
    string restaurantId;
    int? deliveryAddressId;
    decimal totalAmount;
    string status;
    json items;
    string createdAt;
    string updatedAt;
|};

type OrderRow record {|
    string orderId;
    int customerId;
    string restaurantId;
    int? deliveryAddressId;
    decimal totalAmount;
    string status;
    string? itemsJson;
    string createdAt;
    string updatedAt;
|};

//Kafka event contracts (agree these with Person 3 - Order Service) --
# Consumed from topic `orders.created`.
public type OrderCreatedEvent record {
    string orderId;
    int customerId;
    string restaurantId;
    decimal totalAmount;
    int deliveryAddressId?;
    json items?;
    string status?;
};

# Consumed from topic `orders.status.changed`.
public type OrderStatusEvent record {
    string orderId;
    string status;
};

# Produced to topic `customers.registered` (for Notification Service).
public type CustomerRegisteredEvent record {|
    string eventType;
    int customerId;
    string fullName;
    string email;
    string phone;
    string occurredAt;
|};

# Standard error body returned by every endpoint.
public type ErrorBody record {|
    string code;
    string message;
|};
