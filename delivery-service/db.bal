import ballerina/log;
import ballerinax/mysql;
import ballerinax/mysql.driver as _;

// MySQL client + idempotent schema creation. Same DDL is in sql/schema.sql.

final mysql:Client dbClient = check new (
    host = dbHost,
    port = dbPort,
    user = dbUser,
    password = dbPassword,
    database = dbName,
    connectionPool = {maxOpenConnections: 10, minIdleConnections: 1}
);

// Runs once at start-up, before the listeners take traffic
function init() returns error? {
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS drivers (
            id                  INT AUTO_INCREMENT PRIMARY KEY,
            full_name           VARCHAR(120) NOT NULL,
            phone               VARCHAR(20)  NOT NULL,
            vehicle             VARCHAR(40)  NULL,
            plate_number        VARCHAR(20)  NULL,
            status              VARCHAR(12)  NOT NULL DEFAULT 'OFFLINE',
            latitude            DECIMAL(9,6) NULL,
            longitude           DECIMAL(9,6) NULL,
            location_updated_at TIMESTAMP    NULL,
            last_assigned_at    TIMESTAMP    NULL,
            created_at          TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY uq_drivers_phone (phone),
            INDEX idx_drivers_status (status, last_assigned_at),
            CONSTRAINT chk_driver_status CHECK (status IN ('OFFLINE', 'AVAILABLE', 'BUSY'))
        ) ENGINE=InnoDB`);
    // customer/restaurant/address ids are nullable on purpose: if we missed orders.created
    // we still want to be able to deliver the order when READY shows up
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS deliveries (
            order_id            VARCHAR(64) PRIMARY KEY,
            customer_id         INT         NULL,
            restaurant_id       INT         NULL,
            delivery_address_id INT         NULL,
            driver_id           INT         NULL,
            status              VARCHAR(20) NOT NULL,
            ready_at            TIMESTAMP   NULL,
            assigned_at         TIMESTAMP   NULL,
            picked_up_at        TIMESTAMP   NULL,
            delivered_at        TIMESTAMP   NULL,
            created_at          TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at          TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_deliveries_queue (status, ready_at),
            INDEX idx_deliveries_driver (driver_id, status),
            CONSTRAINT fk_deliveries_driver FOREIGN KEY (driver_id) REFERENCES drivers(id)
        ) ENGINE=InnoDB`);
    // one row per thing that happened to a delivery, this is the tracking timeline
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS delivery_events (
            id         INT AUTO_INCREMENT PRIMARY KEY,
            order_id   VARCHAR(64)  NOT NULL,
            status     VARCHAR(20)  NOT NULL,
            note       VARCHAR(200) NULL,
            created_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_events_order (order_id, id),
            CONSTRAINT fk_events_delivery FOREIGN KEY (order_id) REFERENCES deliveries(order_id) ON DELETE CASCADE
        ) ENGINE=InnoDB`);
    log:printInfo("Delivery database schema verified");
}
