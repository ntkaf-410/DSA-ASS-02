import ballerina/sql;


function rowToOrder(OrderRow r, OrderItem[] items) returns OrderRecord => {
    orderId: r.order_id,
    customerId: r.customer_id,
    restaurantId: r.restaurant_id,
    deliveryAddressId: r.delivery_address_id,
    totalAmount: r.total_amount,
    status: r.status,
    paymentStatus: r.payment_status,
    items: items,
    createdAt: r.created_at,
    updatedAt: r.updated_at
};

function getItems(string orderId) returns OrderItem[]|error {
    stream<OrderItem, sql:Error?> s = db->query(`
        SELECT menu_item_id AS menuItemId, name, quantity, unit_price AS unitPrice
        FROM order_items WHERE order_id = ${orderId} ORDER BY id`);
    return check from OrderItem it in s
        select it;
}

public function insertOrder(OrderRecord o) returns error? {
    transaction {
        _ = check db->execute(`
            INSERT INTO orders (order_id, customer_id, restaurant_id, delivery_address_id, total_amount, status)
            VALUES (${o.orderId}, ${o.customerId}, ${o.restaurantId}, ${o.deliveryAddressId}, ${o.totalAmount}, ${o.status})`);
        foreach OrderItem it in o.items {
            _ = check db->execute(`
                INSERT INTO order_items (order_id, menu_item_id, name, quantity, unit_price)
                VALUES (${o.orderId}, ${it.menuItemId}, ${it.name}, ${it.quantity}, ${it.unitPrice})`);
        }
        _ = check db->execute(`
            INSERT INTO order_status_history (order_id, from_status, to_status, source)
            VALUES (${o.orderId}, NULL, ${o.status}, 'order-service')`);
        check commit;
    } on fail error e {
        return e;
    }
}

public function getOrder(string orderId) returns OrderRecord?|error {
    OrderRow|sql:Error row = db->queryRow(`
        SELECT order_id, customer_id, restaurant_id, delivery_address_id, total_amount, status, payment_status,
               DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS created_at,
               DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updated_at
        FROM orders WHERE order_id = ${orderId}`);
    if row is sql:NoRowsError {
        return ();
    }
    if row is error {
        return row;
    }
    return rowToOrder(row, check getItems(orderId));
}

public function listOrders(int? customerId, string? status, int page, int pageSize)
        returns OrderRecord[]|error {
    sql:ParameterizedQuery q = `
        SELECT order_id, customer_id, restaurant_id, delivery_address_id, total_amount, status, payment_status,
               DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS created_at,
               DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updated_at
        FROM orders WHERE 1=1`;
    if customerId is int {
        q = sql:queryConcat(q, ` AND customer_id = ${customerId}`);
    }
    if status is string {
        q = sql:queryConcat(q, ` AND status = ${status}`);
    }
    int offset = (page - 1) * pageSize;
    q = sql:queryConcat(q, ` ORDER BY created_at DESC LIMIT ${pageSize} OFFSET ${offset}`);

    stream<OrderRow, sql:Error?> s = db->query(q);
    OrderRow[] rows = check from OrderRow r in s
        select r;
    OrderRecord[] result = [];
    foreach OrderRow r in rows {
        result.push(rowToOrder(r, check getItems(r.order_id)));
    }
    return result;
}

public function updateStatus(string orderId, string current, string next, string actor)
        returns boolean|error {
    boolean changed = false;
    transaction {
        sql:ExecutionResult r = check db->execute(`
            UPDATE orders SET status = ${next} WHERE order_id = ${orderId} AND status = ${current}`);
        if r.affectedRowCount == 1 {
            _ = check db->execute(`
                INSERT INTO order_status_history (order_id, from_status, to_status, source)
                VALUES (${orderId}, ${current}, ${next}, ${actor})`);
            check commit;
            changed = true;
        } else {
            rollback;
        }
    } on fail error e {
        return e;
    }
    return changed;
}

public function getHistory(string orderId) returns StatusHistoryEntry[]|error {
    stream<StatusHistoryEntry, sql:Error?> s = db->query(`
        SELECT from_status AS fromStatus, to_status AS toStatus, source AS changedBy,
               DATE_FORMAT(changed_at, '%Y-%m-%dT%H:%i:%sZ') AS changedAt
        FROM order_status_history WHERE order_id = ${orderId} ORDER BY id`);
    return check from StatusHistoryEntry e in s
        select e;
}

public function setPaymentStatus(string orderId, string paymentStatus) returns error? {
    _ = check db->execute(`UPDATE orders SET payment_status = ${paymentStatus} WHERE order_id = ${orderId}`);
}
