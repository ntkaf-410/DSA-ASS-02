// ---------------------------------------------------------------------------
// config.bal - all externally configurable values.
// Override with Config.toml (local) or BAL_CONFIG_VAR_<NAME> env vars (Docker),
// e.g. BAL_CONFIG_VAR_DBHOST=mysql, BAL_CONFIG_VAR_KAFKABOOTSTRAP=kafka:19092
// ---------------------------------------------------------------------------

configurable int servicePort = 8081;

// MySQL
configurable string dbHost = "localhost";
configurable int dbPort = 3306;
configurable string dbUser = "root";
configurable string dbPassword = "root";
configurable string dbName = "customer_db";

// Kafka
configurable string kafkaBootstrap = "localhost:9092";
configurable string consumerGroupId = "customer-service-group";
configurable string customerRegisteredTopic = "customers.registered"; // produced
configurable string orderCreatedTopic = "orders.created";             // consumed
configurable string orderStatusTopic = "orders.status.changed";       // consumed
