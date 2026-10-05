// Override with Config.toml locally or BAL_CONFIG_VAR_<NAME> env vars in Docker.

configurable int servicePort = 8082;

// MySQL
configurable string dbHost = "localhost";
configurable int dbPort = 3306;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "restaurant_db";

// Kafka
configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroupId = "restaurant-service-group";
configurable string orderCreatedTopic = "orders.created";           // consumed
configurable string orderStatusTopic = "orders.status.changed";     // consumed
configurable string restaurantOrderTopic = "restaurants.order.status"; // produced
configurable string lowStockTopic = "restaurants.stock.low";        // produced

// Business rules
configurable int lowStockThreshold = 5;
configurable int utcOffsetSeconds = 7200; // Namibia is UTC+2, no daylight saving
