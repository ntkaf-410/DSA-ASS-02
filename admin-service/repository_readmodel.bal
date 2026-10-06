// Write side of the read model: one small upsert per Kafka event.
//
// `at` is the Kafka record timestamp in seconds, not "now". That way replaying a topic
// (new consumer group, rebuilt database) puts every order back on the day it really happened
// instead of piling the whole history onto today.
//
// Everything is an upsert because Kafka is at-least-once and because events from different
// topics can overtake each other, e.g. payments.completed arriving before orders.created.

function applyOrderCreated(string orderId, int? customerId, int? restaurantId, decimal? totalAmount, decimal at)
        returns error? {
    // if a status/payment event got here first there is already a stub row: fill in the
    // details but leave its status alone, it is newer than CREATED
    _ = check dbClient->execute(`
        INSERT INTO rpt_orders (order_id, customer_id, restaurant_id, total_amount, status, created_at, updated_at)
        VALUES (${orderId}, ${customerId}, ${restaurantId}, ${totalAmount}, 'CREATED',
                FROM_UNIXTIME(${at}), FROM_UNIXTIME(${at}))
        ON DUPLICATE KEY UPDATE
            customer_id = ${customerId},
            restaurant_id = COALESCE(${restaurantId}, restaurant_id),
            total_amount = ${totalAmount},
            created_at = LEAST(created_at, FROM_UNIXTIME(${at}))`);
}

function applyOrderStatus(string orderId, string status, decimal at) returns error? {
    // the updated_at check stops an old duplicate from dragging the order backwards.
    // status is assigned before updated_at on purpose, MySQL evaluates these left to right.
    _ = check dbClient->execute(`
        INSERT INTO rpt_orders (order_id, status, created_at, updated_at, delivered_at)
        VALUES (${orderId}, ${status}, FROM_UNIXTIME(${at}), FROM_UNIXTIME(${at}),
                IF(${status} = 'DELIVERED', FROM_UNIXTIME(${at}), NULL))
        ON DUPLICATE KEY UPDATE
            status = IF(updated_at <= FROM_UNIXTIME(${at}), ${status}, status),
            delivered_at = IF(${status} = 'DELIVERED', FROM_UNIXTIME(${at}), delivered_at),
            updated_at = GREATEST(updated_at, FROM_UNIXTIME(${at}))`);
}

function applyPayment(string orderId, string paymentStatus, decimal at) returns error? {
    _ = check dbClient->execute(`
        INSERT INTO rpt_orders (order_id, payment_status, created_at, updated_at)
        VALUES (${orderId}, ${paymentStatus}, FROM_UNIXTIME(${at}), FROM_UNIXTIME(${at}))
        ON DUPLICATE KEY UPDATE payment_status = ${paymentStatus}`);
}

// We only keep the restaurant's reason for saying no. The status itself reaches us through
// orders.status.changed once the Order Service has accepted the kitchen's decision.
function applyRestaurantDecision(string orderId, int? restaurantId, string? reason, decimal at) returns error? {
    _ = check dbClient->execute(`
        INSERT INTO rpt_orders (order_id, restaurant_id, reject_reason, created_at, updated_at)
        VALUES (${orderId}, ${restaurantId}, ${reason}, FROM_UNIXTIME(${at}), FROM_UNIXTIME(${at}))
        ON DUPLICATE KEY UPDATE
            restaurant_id = COALESCE(restaurant_id, ${restaurantId}),
            reject_reason = COALESCE(${reason}, reject_reason)`);
}

function applyCustomerRegistered(int customerId, string fullName, string email, decimal at) returns error? {
    _ = check dbClient->execute(`
        INSERT INTO rpt_customers (customer_id, full_name, email, registered_at)
        VALUES (${customerId}, ${fullName}, ${email}, FROM_UNIXTIME(${at}))
        ON DUPLICATE KEY UPDATE full_name = ${fullName}, email = ${email}`);
}

function applyDeliveryAssigned(string orderId, int? driverId, string? driverName, decimal at) returns error? {
    // a re-assignment (first driver dropped out) simply overwrites the driver
    _ = check dbClient->execute(`
        INSERT INTO rpt_deliveries (order_id, driver_id, driver_name, status, assigned_at, updated_at)
        VALUES (${orderId}, ${driverId}, ${driverName}, 'ASSIGNED', FROM_UNIXTIME(${at}), FROM_UNIXTIME(${at}))
        ON DUPLICATE KEY UPDATE
            driver_id = COALESCE(${driverId}, driver_id),
            driver_name = COALESCE(${driverName}, driver_name),
            assigned_at = COALESCE(assigned_at, FROM_UNIXTIME(${at}))`);
}

function applyDeliveryStatus(string orderId, string status, int? driverId, decimal at) returns error? {
    _ = check dbClient->execute(`
        INSERT INTO rpt_deliveries (order_id, driver_id, status, picked_up_at, delivered_at, updated_at)
        VALUES (${orderId}, ${driverId}, ${status},
                IF(${status} = 'OUT_FOR_DELIVERY', FROM_UNIXTIME(${at}), NULL),
                IF(${status} = 'DELIVERED', FROM_UNIXTIME(${at}), NULL),
                FROM_UNIXTIME(${at}))
        ON DUPLICATE KEY UPDATE
            status = IF(updated_at <= FROM_UNIXTIME(${at}), ${status}, status),
            driver_id = COALESCE(${driverId}, driver_id),
            picked_up_at = IF(${status} = 'OUT_FOR_DELIVERY', FROM_UNIXTIME(${at}), picked_up_at),
            delivered_at = IF(${status} = 'DELIVERED', FROM_UNIXTIME(${at}), delivered_at),
            updated_at = GREATEST(updated_at, FROM_UNIXTIME(${at}))`);
}


function recordLowStock(string eventKey, int restaurantId, int menuItemId, string itemName, int stockQuantity,
        decimal at) returns error? {
    _ = check dbClient->execute(`
        INSERT IGNORE INTO rpt_low_stock (event_key, restaurant_id, menu_item_id, item_name, stock_quantity, occurred_at)
        VALUES (${eventKey}, ${restaurantId}, ${menuItemId}, ${itemName}, ${stockQuantity}, FROM_UNIXTIME(${at}))`);
}
