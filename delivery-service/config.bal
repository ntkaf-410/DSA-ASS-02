// Override with Config.toml locally or BAL_CONFIG_VAR_<NAME> env vars in Docker.

configurable int servicePort = 8085;

// MySQL
configurable string dbHost = "localhost";
configurable int dbPort = 3310;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "delivery_db";

// Kafka
configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroupId = "delivery-service-group";
configurable string orderCreatedTopic = "orders.created";                // consumed
configurable string orderStatusTopic = "orders.status.changed";          // consumed
configurable string driverAssignedTopic = "deliveries.driver.assigned";  // produced
configurable string deliveryStatusTopic = "deliveries.status.changed";   // produced
configurable string driverLocationTopic = "deliveries.location.updated"; // produced

// Business rules
// how many free drivers / queued orders we look at in one assignment pass
configurable int maxAssignAttempts = 5;
