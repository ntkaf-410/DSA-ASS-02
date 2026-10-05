// Override with Config.toml locally or BAL_CONFIG_VAR_<NAME> env vars in Docker.

configurable int servicePort = 8087;

// MySQL
configurable string dbHost = "localhost";
configurable int dbPort = 3306;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "admin_db";

// Kafka. We only consume, the admin side never publishes anything.
configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroupId = "admin-service-group";
configurable string customerRegisteredTopic = "customers.registered";
configurable string orderCreatedTopic = "orders.created";
configurable string orderStatusTopic = "orders.status.changed";
configurable string restaurantOrderTopic = "restaurants.order.status";
configurable string lowStockTopic = "restaurants.stock.low";
configurable string paymentCompletedTopic = "payments.completed";
configurable string paymentFailedTopic = "payments.failed";
configurable string driverAssignedTopic = "deliveries.driver.assigned";
configurable string deliveryStatusTopic = "deliveries.status.changed";

// Where the other services live, only used by GET /admin/services to ping their /health
configurable string customerServiceUrl = "http://localhost:8081";
configurable string restaurantServiceUrl = "http://localhost:8082";
configurable string orderServiceUrl = "http://localhost:8083";
configurable string paymentServiceUrl = "http://localhost:8084";
configurable string deliveryServiceUrl = "http://localhost:8085";
configurable string notificationServiceUrl = "http://localhost:8086";
configurable decimal healthTimeoutSeconds = 3;
