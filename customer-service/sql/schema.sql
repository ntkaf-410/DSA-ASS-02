-- Customer Service schema (also auto-applied by db.bal at start-up)
CREATE DATABASE IF NOT EXISTS customer_db;
USE customer_db;

CREATE TABLE IF NOT EXISTS customers (
    id            INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(120) NOT NULL,
    email         VARCHAR(190) NOT NULL UNIQUE,
    phone         VARCHAR(20)  NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS addresses (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    customer_id INT NOT NULL,
    label       VARCHAR(50)  NOT NULL,
    street      VARCHAR(190) NOT NULL,
    city        VARCHAR(100) NOT NULL,
    region      VARCHAR(100) NULL,
    postal_code VARCHAR(20)  NULL,
    country     VARCHAR(100) NOT NULL DEFAULT 'Namibia',
    latitude    DECIMAL(9,6) NULL,
    longitude   DECIMAL(9,6) NULL,
    is_default  BOOLEAN NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_addresses_customer (customer_id),
    CONSTRAINT fk_addresses_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_history (
    order_id            VARCHAR(64) PRIMARY KEY,
    customer_id         INT NOT NULL,
    restaurant_id       VARCHAR(64) NOT NULL,
    delivery_address_id INT NULL,
    total_amount        DECIMAL(12,2) NOT NULL DEFAULT 0,
    status              VARCHAR(32) NOT NULL,
    items_json          TEXT NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_orders_customer (customer_id, created_at),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id)
        REFERENCES customers(id) ON DELETE CASCADE
) ENGINE=InnoDB;
