CREATE DATABASE IF NOT EXISTS payment_db;
USE payment_db;

CREATE TABLE IF NOT EXISTS payments (
    order_id       VARCHAR(64) PRIMARY KEY,
    customer_id    INT NOT NULL,
    amount         DECIMAL(10,2) NOT NULL,
    currency       CHAR(3) NOT NULL DEFAULT 'NAD',
    status         VARCHAR(12) NOT NULL,
    failure_reason VARCHAR(200) NULL,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT chk_payment_amount CHECK (amount >= 0),
    CONSTRAINT chk_payment_status CHECK (status IN ('COMPLETED', 'FAILED'))
) ENGINE=InnoDB;
