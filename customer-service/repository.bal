import ballerina/lang.value;
import ballerina/sql;


// repository.bal - every SQL statement lives here (parameterised -> no SQL
// injection). Service/Kafka code never builds SQL itself.

// CUSTOMERS

function insertCustomer(string fullName, string email, string phone, string passwordHash) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(`
        INSERT INTO customers (full_name, email, phone, password_hash)
        VALUES (${fullName}, ${email}, ${phone}, ${passwordHash})`);
    string|int? id = res.lastInsertId;
    if id is int {
        return id;
    }
    return error("Could not read generated customer id");
}

function customerSelect() returns sql:ParameterizedQuery =>
    `SELECT id, full_name AS fullName, email, phone,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt
     FROM customers`;

function getCustomerById(int id) returns Customer|sql:Error {
    return dbClient->queryRow(sql:queryConcat(customerSelect(), ` WHERE id = ${id}`));
}

function getCredentialsByEmail(string email) returns CredentialRow|sql:Error {
    return dbClient->queryRow(
        `SELECT id, password_hash AS passwordHash FROM customers WHERE email = ${email}`);
}

function listCustomers(int pageSize, int offset) returns Customer[]|error {
    stream<Customer, sql:Error?> rs = dbClient->query(
        sql:queryConcat(customerSelect(), ` ORDER BY id LIMIT ${pageSize} OFFSET ${offset}`));
    return from Customer c in rs
        select c;
}

function customerExists(int id) returns boolean|error {
    int n = check dbClient->queryRow(`SELECT COUNT(*) FROM customers WHERE id = ${id}`);
    return n > 0;
}

function updateCustomer(int id, string fullName, string phone) returns error? {
    _ = check dbClient->execute(
        `UPDATE customers SET full_name = ${fullName}, phone = ${phone} WHERE id = ${id}`);
}

function deleteCustomer(int id) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(`DELETE FROM customers WHERE id = ${id}`);
    return res.affectedRowCount ?: 0;
}

//ADDRESSES

function addressSelect() returns sql:ParameterizedQuery =>
    `SELECT id, customer_id AS customerId, label, street, city, region,
            postal_code AS postalCode, country, latitude, longitude,
            is_default AS isDefault
     FROM addresses`;

# Inserts an address inside a transaction. The customer's first address (or one
# flagged isDefault) becomes the default and any previous default is cleared.
function insertAddress(int customerId, AddressInput a) returns int|error {
    int newId = 0;
    string country = a.country ?: "Namibia";
    transaction {
        int existing = check dbClient->queryRow(
            `SELECT COUNT(*) FROM addresses WHERE customer_id = ${customerId}`);
        boolean makeDefault = (a.isDefault ?: false) || existing == 0;
        if makeDefault {
            _ = check dbClient->execute(
                `UPDATE addresses SET is_default = FALSE WHERE customer_id = ${customerId}`);
        }
        sql:ExecutionResult res = check dbClient->execute(`
            INSERT INTO addresses (customer_id, label, street, city, region, postal_code,
                                   country, latitude, longitude, is_default)
            VALUES (${customerId}, ${a.label}, ${a.street}, ${a.city}, ${a.region},
                    ${a.postalCode}, ${country}, ${a.latitude}, ${a.longitude}, ${makeDefault})`);
        string|int? id = res.lastInsertId;
        if id is int {
            newId = id;
        } else {
            rollback;
            return error("Could not read generated address id");
        }
        check commit;
    }
    return newId;
}

function listAddresses(int customerId) returns Address[]|error {
    stream<Address, sql:Error?> rs = dbClient->query(
        sql:queryConcat(addressSelect(),
        ` WHERE customer_id = ${customerId} ORDER BY is_default DESC, id`));
    return from Address a in rs
        select a;
}

function getAddress(int customerId, int addressId) returns Address|sql:Error {
    return dbClient->queryRow(sql:queryConcat(addressSelect(),
        ` WHERE id = ${addressId} AND customer_id = ${customerId}`));
}

function updateAddress(int customerId, int addressId, AddressInput a) returns error? {
    string country = a.country ?: "Namibia";
    _ = check dbClient->execute(`
        UPDATE addresses
        SET label = ${a.label}, street = ${a.street}, city = ${a.city}, region = ${a.region},
            postal_code = ${a.postalCode}, country = ${country},
            latitude = ${a.latitude}, longitude = ${a.longitude}
        WHERE id = ${addressId} AND customer_id = ${customerId}`);
}

# Deletes an address; if it was the default, the oldest remaining one is promoted.
function deleteAddress(int customerId, int addressId) returns int|error {
    int deleted = 0;
    transaction {
        sql:ExecutionResult res = check dbClient->execute(
            `DELETE FROM addresses WHERE id = ${addressId} AND customer_id = ${customerId}`);
        deleted = res.affectedRowCount ?: 0;
        int defaults = check dbClient->queryRow(
            `SELECT COUNT(*) FROM addresses WHERE customer_id = ${customerId} AND is_default = TRUE`);
        if deleted > 0 && defaults == 0 {
            _ = check dbClient->execute(
                `UPDATE addresses SET is_default = TRUE WHERE customer_id = ${customerId} ORDER BY id LIMIT 1`);
        }
        check commit;
    }
    return deleted;
}

# Atomically makes one address the default. Returns false if it does not exist.
function setDefaultAddress(int customerId, int addressId) returns boolean|error {
    transaction {
        int owned = check dbClient->queryRow(
            `SELECT COUNT(*) FROM addresses WHERE id = ${addressId} AND customer_id = ${customerId}`);
        if owned == 0 {
            rollback;
            return false;
        }
        _ = check dbClient->execute(
            `UPDATE addresses SET is_default = FALSE WHERE customer_id = ${customerId}`);
        _ = check dbClient->execute(
            `UPDATE addresses SET is_default = TRUE WHERE id = ${addressId} AND customer_id = ${customerId}`);
        check commit;
    }
    return true;
}

//ORDER HISTORY

function orderSelect() returns sql:ParameterizedQuery =>
    `SELECT order_id AS orderId, customer_id AS customerId, restaurant_id AS restaurantId,
            delivery_address_id AS deliveryAddressId, total_amount AS totalAmount, status,
            items_json AS itemsJson,
            DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%s') AS createdAt,
            DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%s') AS updatedAt
     FROM order_history`;

function toOrderSummary(OrderRow r) returns OrderSummary|error {
    json items = ();
    string? raw = r.itemsJson;
    if raw is string {
        items = check value:fromJsonString(raw);
    }
    return {
        orderId: r.orderId,
        customerId: r.customerId,
        restaurantId: r.restaurantId,
        deliveryAddressId: r.deliveryAddressId,
        totalAmount: r.totalAmount,
        status: r.status,
        items,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt
    };
}

# Idempotent: re-delivery of the same `orders.created` event never duplicates a
# row and never rolls the status backwards (status is not touched on conflict).
function upsertOrder(OrderCreatedEvent e) returns error? {
    json? items = e?.items;
    string? itemsJson = items is () ? () : items.toJsonString();
    string status = e?.status ?: "CREATED";
    int? addressId = e?.deliveryAddressId;
    _ = check dbClient->execute(`
        INSERT INTO order_history (order_id, customer_id, restaurant_id, delivery_address_id,
                                   total_amount, status, items_json)
        VALUES (${e.orderId}, ${e.customerId}, ${e.restaurantId}, ${addressId},
                ${e.totalAmount}, ${status}, ${itemsJson})
        ON DUPLICATE KEY UPDATE
            restaurant_id = VALUES(restaurant_id),
            delivery_address_id = VALUES(delivery_address_id),
            total_amount = VALUES(total_amount),
            items_json = VALUES(items_json)`);
}

function updateOrderStatus(string orderId, string status) returns int|error {
    sql:ExecutionResult res = check dbClient->execute(
        `UPDATE order_history SET status = ${status} WHERE order_id = ${orderId}`);
    return res.affectedRowCount ?: 0;
}

function listOrders(int customerId, string? status, int pageSize, int offset) returns OrderSummary[]|error {
    sql:ParameterizedQuery q = sql:queryConcat(orderSelect(), ` WHERE customer_id = ${customerId}`);
    if status is string {
        q = sql:queryConcat(q, ` AND status = ${status}`);
    }
    q = sql:queryConcat(q, ` ORDER BY created_at DESC LIMIT ${pageSize} OFFSET ${offset}`);
    stream<OrderRow, sql:Error?> rs = dbClient->query(q);
    OrderRow[] rows = check from OrderRow r in rs
        select r;
    OrderSummary[] result = [];
    foreach OrderRow r in rows {
        result.push(check toOrderSummary(r));
    }
    return result;
}

function getOrder(int customerId, string orderId) returns OrderSummary|error {
    OrderRow row = check dbClient->queryRow(sql:queryConcat(orderSelect(),
        ` WHERE order_id = ${orderId} AND customer_id = ${customerId}`));
    return toOrderSummary(row);
}
