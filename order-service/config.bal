configurable int port = 8083;

configurable string dbHost = "localhost";
configurable int dbPort = 3306;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "order_db";

configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroup = "order-service-group";

configurable string topicOrderCreated = "orders.created";
configurable string topicOrderStatusChanged = "orders.status.changed";

configurable string topicPaymentCompleted = "payments.completed";
configurable string topicPaymentFailed = "payments.failed";
configurable string topicDeliveryStatus = "deliveries.status.changed";
configurable string topicRestaurantOrderStatus = "restaurants.order.status"; // Person 2

configurable string customerServiceUrl = "http://localhost:8081";
configurable string restaurantServiceUrl = "http://localhost:8082";
