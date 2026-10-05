import ballerina/log;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

final mysql:Client dbClient = check new (
    host = dbHost,
    port = dbPort,
    user = dbUser,
    password = dbPassword,
    database = dbName,
    connectionPool = {maxOpenConnections: 10, minIdleConnections: 1}
);

// admin_db is a read model: every table here is filled from Kafka and can be rebuilt
// from scratch by dropping it and resetting the consumer group. Nothing in it is the
// source of truth, so we never reach into another service's database for a report.
function init() returns error? {
    // customer_id/restaurant_id/total_amount are nullable because a status event can
    // reach us before the matching orders.created (different topics, no ordering between them)
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS rpt_orders (
            order_id       VARCHAR(64)   PRIMARY KEY,
            customer_id    INT           NULL,
            restaurant_id  INT           NULL,
            total_amount   DECIMAL(10,2) NULL,
            status         VARCHAR(20)   NOT NULL DEFAULT 'CREATED',
            payment_status VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
            reject_reason  VARCHAR(200)  NULL,
            created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
            delivered_at   TIMESTAMP     NULL,
            INDEX idx_rpt_orders_status (status),
            INDEX idx_rpt_orders_created (created_at),
            INDEX idx_rpt_orders_restaurant (restaurant_id),
            INDEX idx_rpt_orders_customer (customer_id)
        ) ENGINE=InnoDB`);
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS rpt_customers (
            customer_id   INT          PRIMARY KEY,
            full_name     VARCHAR(120) NOT NULL,
            email         VARCHAR(160) NOT NULL,
            registered_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
        ) ENGINE=InnoDB`);
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS rpt_deliveries (
            order_id     VARCHAR(64)  PRIMARY KEY,
            driver_id    INT          NULL,
            driver_name  VARCHAR(120) NULL,
            status       VARCHAR(20)  NOT NULL DEFAULT 'ASSIGNED',
            assigned_at  TIMESTAMP    NULL,
            picked_up_at TIMESTAMP    NULL,
            delivered_at TIMESTAMP    NULL,
            updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_rpt_deliveries_driver (driver_id),
            INDEX idx_rpt_deliveries_status (status)
        ) ENGINE=InnoDB`);
    // event_key identifies the Kafka record, so a redelivered one can't be logged twice
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS rpt_low_stock (
            id             BIGINT AUTO_INCREMENT PRIMARY KEY,
            event_key      VARCHAR(160) NOT NULL UNIQUE,
            restaurant_id  INT          NOT NULL,
            menu_item_id   INT          NOT NULL,
            item_name      VARCHAR(120) NOT NULL,
            stock_quantity INT          NOT NULL,
            occurred_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_rpt_low_stock_time (occurred_at)
        ) ENGINE=InnoDB`);
    log:printInfo("Admin reporting schema verified");
}
