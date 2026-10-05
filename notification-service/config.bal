// Override with Config.toml locally or BAL_CONFIG_VAR_<NAME> env vars in Docker.

configurable int servicePort = 8086;

// MySQL
configurable string dbHost = "localhost";
configurable int dbPort = 3311;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "notification_db";

// Kafka. This service only listens, it never produces.
configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroupId = "notification-service-group";
configurable string customerRegisteredTopic = "customers.registered";   // Customer Service
configurable string orderCreatedTopic = "orders.created";               // Order Service
configurable string orderStatusTopic = "orders.status.changed";         // Order Service
configurable string paymentCompletedTopic = "payments.completed";       // Payment Service
configurable string paymentFailedTopic = "payments.failed";             // Payment Service
configurable string lowStockTopic = "restaurants.stock.low";            // Restaurant Service
configurable string driverAssignedTopic = "deliveries.driver.assigned"; // Delivery Service
configurable string deliveryStatusTopic = "deliveries.status.changed";  // Delivery Service

// Only used as a fallback when we have no contact details for a customer yet
configurable string customerServiceUrl = "http://localhost:8081";
