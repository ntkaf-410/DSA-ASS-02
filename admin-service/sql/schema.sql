-- Same DDL the service runs on startup (db.bal), kept here for manual setup and the report.
-- All of it is a read model filled from Kafka, safe to drop and rebuild.
CREATE DATABASE IF NOT EXISTS admin_db;
USE admin_db;

-- customer_id / restaurant_id / total_amount are nullable: a status or payment event can
-- arrive before orders.created and creates a stub row that gets filled in later
CREATE TABLE IF NOT EXISTS rpt_orders (
    order_id       VARCHAR(64)   PRIMARY KEY,
    customer_id    INT           NULL,
    restaurant_id  INT           NULL,
    total_amount   DECIMAL(10,2) NULL,
    status         VARCHAR(20)   NOT NULL DEFAULT 'CREATED',
    payment_status VARCHAR(10)   NOT NULL DEFAULT 'PENDING',   -- PENDING | PAID | FAILED
    reject_reason  VARCHAR(200)  NULL,
    created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    delivered_at   TIMESTAMP     NULL,
    INDEX idx_rpt_orders_status (status),
    INDEX idx_rpt_orders_created (created_at),
    INDEX idx_rpt_orders_restaurant (restaurant_id),
    INDEX idx_rpt_orders_customer (customer_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS rpt_customers (
    customer_id   INT          PRIMARY KEY,
    full_name     VARCHAR(120) NOT NULL,
    email         VARCHAR(160) NOT NULL,
    registered_at TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS rpt_deliveries (
    order_id     VARCHAR(64)  PRIMARY KEY,
    driver_id    INT          NULL,
    driver_name  VARCHAR(120) NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'ASSIGNED',   -- ASSIGNED | OUT_FOR_DELIVERY | DELIVERED | CANCELLED
    assigned_at  TIMESTAMP    NULL,
    picked_up_at TIMESTAMP    NULL,
    delivered_at TIMESTAMP    NULL,
    updated_at   TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_rpt_deliveries_driver (driver_id),
    INDEX idx_rpt_deliveries_status (status)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS rpt_low_stock (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_key      VARCHAR(160) NOT NULL UNIQUE,   -- identifies the Kafka record, blocks duplicates
    restaurant_id  INT          NOT NULL,
    menu_item_id   INT          NOT NULL,
    item_name      VARCHAR(120) NOT NULL,
    stock_quantity INT          NOT NULL,
    occurred_at    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_rpt_low_stock_time (occurred_at)
) ENGINE=InnoDB;
