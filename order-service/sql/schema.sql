CREATE TABLE IF NOT EXISTS orders (
    order_id            VARCHAR(36)   PRIMARY KEY,
    customer_id         INT           NOT NULL,
    restaurant_id       INT           NOT NULL,
    delivery_address_id INT           NOT NULL,
    total_amount        DECIMAL(10,2) NOT NULL,
    status              VARCHAR(20)   NOT NULL,
            payment_status      VARCHAR(10)   NOT NULL DEFAULT 'PENDING',
    created_at          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_orders_customer (customer_id, created_at),
    INDEX idx_orders_status (status)
);
CREATE TABLE IF NOT EXISTS order_items (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(36) NOT NULL, menu_item_id INT NOT NULL, name VARCHAR(120) NOT NULL,
    quantity INT NOT NULL, unit_price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS order_status_history (
    id INT AUTO_INCREMENT PRIMARY KEY,
    order_id VARCHAR(36) NOT NULL, from_status VARCHAR(20) NULL, to_status VARCHAR(20) NOT NULL,
    source VARCHAR(40) NOT NULL, changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hist_order (order_id),
    FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE
);
