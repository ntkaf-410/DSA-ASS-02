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

function init() returns error? {
    _ = check dbClient->execute(`
        CREATE TABLE IF NOT EXISTS payments (
            order_id      VARCHAR(64) PRIMARY KEY,
            customer_id   INT NOT NULL,
            amount        DECIMAL(10,2) NOT NULL,
            currency      CHAR(3) NOT NULL DEFAULT 'NAD',
            status        VARCHAR(12) NOT NULL,
            failure_reason VARCHAR(200) NULL,
            created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            CONSTRAINT chk_payment_amount CHECK (amount >= 0),
            CONSTRAINT chk_payment_status CHECK (status IN ('COMPLETED', 'FAILED'))
        ) ENGINE=InnoDB`);
    log:printInfo("Payment database schema verified");
}
