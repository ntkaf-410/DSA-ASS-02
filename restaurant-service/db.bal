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
    connectionPool = {maxOpenConnections: 15, minIdleConnections: 2}
);

// Runs once at start-up, before the listeners take traffic
function init() returns error? {
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS restaurants (
            id          INT AUTO_INCREMENT PRIMARY KEY,
            name        VARCHAR(150) NOT NULL,
            description VARCHAR(500) NULL,
            cuisine     VARCHAR(60)  NOT NULL,
            phone       VARCHAR(20)  NOT NULL,
            address     VARCHAR(190) NOT NULL,
            city        VARCHAR(100) NOT NULL,
            latitude    DECIMAL(9,6) NULL,
            longitude   DECIMAL(9,6) NULL,
            is_active   BOOLEAN NOT NULL DEFAULT TRUE,
            created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_restaurant_branch (name, address),
            INDEX idx_restaurants_city (city, cuisine)
        ) ENGINE=InnoDB`);

    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS opening_hours (
            restaurant_id INT NOT NULL,
            day_of_week   TINYINT NOT NULL,
            open_time     TIME NULL,
            close_time    TIME NULL,
            is_closed     BOOLEAN NOT NULL DEFAULT FALSE,
            PRIMARY KEY (restaurant_id, day_of_week),
            CONSTRAINT fk_hours_restaurant FOREIGN KEY (restaurant_id)
                REFERENCES restaurants(id) ON DELETE CASCADE
        ) ENGINE=InnoDB`);

    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS menu_items (
            id             INT AUTO_INCREMENT PRIMARY KEY,
            restaurant_id  INT NOT NULL,
            name           VARCHAR(150) NOT NULL,
            description    VARCHAR(500) NULL,
            category       VARCHAR(60)  NOT NULL,
            price          DECIMAL(10,2) NOT NULL,
            is_available   BOOLEAN NOT NULL DEFAULT TRUE,
            stock_quantity INT NOT NULL DEFAULT 0,
            created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uq_menu_item (restaurant_id, name),
            INDEX idx_menu_category (restaurant_id, category),
            CONSTRAINT chk_price CHECK (price > 0),
            CONSTRAINT chk_stock CHECK (stock_quantity >= 0),
            CONSTRAINT fk_menu_restaurant FOREIGN KEY (restaurant_id)
                REFERENCES restaurants(id) ON DELETE CASCADE
        ) ENGINE=InnoDB`);

    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS kitchen_orders (
            order_id      VARCHAR(64) PRIMARY KEY,
            restaurant_id INT NOT NULL,
            customer_id   INT NULL,
            status        VARCHAR(20) NOT NULL,
            reject_reason VARCHAR(200) NULL,
            items_json    TEXT NULL,
            created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_kitchen_restaurant (restaurant_id, status, created_at)
        ) ENGINE=InnoDB`);

    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS stock_reservations (
            order_id     VARCHAR(64) NOT NULL,
            menu_item_id INT NOT NULL,
            quantity     INT NOT NULL,
            PRIMARY KEY (order_id, menu_item_id)
        ) ENGINE=InnoDB`);

    log:printInfo("Restaurant database schema verified");
}
