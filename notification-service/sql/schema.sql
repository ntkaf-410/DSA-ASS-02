CREATE DATABASE IF NOT EXISTS notification_db;
USE notification_db;

CREATE TABLE IF NOT EXISTS contacts (
    customer_id INT          PRIMARY KEY,
    full_name   VARCHAR(120) NOT NULL,
    email       VARCHAR(160) NOT NULL,
    phone       VARCHAR(20)  NOT NULL,
    updated_at  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS order_refs (
    order_id      VARCHAR(64) PRIMARY KEY,
    customer_id   INT         NOT NULL,
    restaurant_id INT         NOT NULL,
    created_at    TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS notifications (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    recipient_type VARCHAR(12)  NOT NULL,
    recipient_id   INT          NOT NULL,
    order_id       VARCHAR(64)  NULL,
    event_type     VARCHAR(40)  NOT NULL,
    channel        VARCHAR(10)  NOT NULL,
    destination    VARCHAR(160) NULL,
    title          VARCHAR(120) NOT NULL,
    message        VARCHAR(500) NOT NULL,
    status         VARCHAR(10)  NOT NULL DEFAULT 'SENT',
    is_read        BOOLEAN      NOT NULL DEFAULT FALSE,
    dedupe_key     VARCHAR(120) NULL,
    created_at     TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_notifications_dedupe (dedupe_key),
    INDEX idx_notifications_inbox (recipient_type, recipient_id, id),
    INDEX idx_notifications_order (order_id)
) ENGINE=InnoDB;
