configurable int servicePort = 8084;

// MySQL
configurable string dbHost = "localhost";
configurable int dbPort = 3309;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "payment_db";

// Kafka
configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroupId = "payment-service-group";
configurable string orderCreatedTopic = "orders.created";
configurable string paymentCompletedTopic = "payments.completed";
configurable string paymentFailedTopic = "payments.failed";

// Enable to simulate a declined payment for every incoming order
configurable boolean simulatePaymentFailure = false;
