import ballerina/sql;

// Read side: the queries behind /admin/reports/*.
//
// "Revenue" means the same thing in every report: orders that were paid and not cancelled.
// A cancelled order that was already charged is a refund case, not income.

function orderTotals() returns OrderTotalsRow|sql:Error {
    return dbClient->queryRow(`
        SELECT COUNT(*) AS totalOrders,
               COUNT(CASE WHEN status NOT IN ('DELIVERED', 'CANCELLED') THEN 1 END) AS activeOrders,
               COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) AS deliveredOrders,
               COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) AS cancelledOrders,
               COUNT(CASE WHEN payment_status = 'PAID' AND status <> 'CANCELLED' THEN 1 END) AS paidOrders,
               COALESCE(SUM(CASE WHEN payment_status = 'PAID' AND status <> 'CANCELLED' THEN total_amount END), 0)
                   AS grossRevenue,
               ROUND(AVG(CASE WHEN delivered_at IS NOT NULL
                              THEN TIMESTAMPDIFF(MINUTE, created_at, delivered_at) END), 1) AS averageDeliveryMinutes
        FROM rpt_orders`);
}

function countCustomers() returns int|sql:Error {
    return dbClient->queryRow(`SELECT COUNT(*) FROM rpt_customers`);
}

function countCompletedDeliveries() returns int|sql:Error {
    return dbClient->queryRow(`SELECT COUNT(*) FROM rpt_deliveries WHERE status = 'DELIVERED'`);
}


function ordersByStatus() returns StatusCount[]|error {
    stream<StatusCount, sql:Error?> rs = dbClient->query(`
        SELECT status, COUNT(*) AS orders, COALESCE(SUM(total_amount), 0) AS totalAmount
        FROM rpt_orders
        GROUP BY status
        ORDER BY orders DESC`);
    return from StatusCount r in rs
        select r;
}

// One row per day that had orders. Days without any order are simply missing,
// the dashboard can fill the gaps with zeros if it wants a continuous line.
function dailyRevenue(int days) returns DailyRevenue[]|error {
    stream<DailyRevenue, sql:Error?> rs = dbClient->query(`
        SELECT DATE_FORMAT(created_at, '%Y-%m-%d') AS orderDate,
               COUNT(*) AS orders,
               COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) AS cancelled,
               COALESCE(SUM(CASE WHEN payment_status = 'PAID' AND status <> 'CANCELLED' THEN total_amount END), 0)
                   AS revenue
        FROM rpt_orders
        WHERE created_at >= DATE_SUB(CURRENT_DATE, INTERVAL ${days} DAY)
        GROUP BY orderDate
        ORDER BY orderDate`);
    return from DailyRevenue r in rs
        select r;
}

function topRestaurants(int max) returns RestaurantReport[]|error {
    stream<RestaurantReport, sql:Error?> rs = dbClient->query(`
        SELECT restaurant_id AS restaurantId,
               COUNT(*) AS orders,
               COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) AS delivered,
               COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) AS cancelled,
               COALESCE(SUM(CASE WHEN payment_status = 'PAID' AND status <> 'CANCELLED' THEN total_amount END), 0)
                   AS revenue
        FROM rpt_orders
        WHERE restaurant_id IS NOT NULL
        GROUP BY restaurant_id
        ORDER BY revenue DESC, orders DESC
        LIMIT ${max}`);
    return from RestaurantReport r in rs
        select r;
}

// LEFT JOIN: someone who registered before this service existed still shows up, just without a name
function topCustomers(int max) returns CustomerReport[]|error {
    stream<CustomerReport, sql:Error?> rs = dbClient->query(`
        SELECT o.customer_id AS customerId, c.full_name AS fullName, c.email AS email,
               COUNT(*) AS orders,
               COALESCE(SUM(CASE WHEN o.payment_status = 'PAID' AND o.status <> 'CANCELLED' THEN o.total_amount END), 0)
                   AS spent
        FROM rpt_orders o
        LEFT JOIN rpt_customers c ON c.customer_id = o.customer_id
        WHERE o.customer_id IS NOT NULL
        GROUP BY o.customer_id, c.full_name, c.email
        ORDER BY spent DESC, orders DESC
        LIMIT ${max}`);
    return from CustomerReport r in rs
        select r;
}

function driverPerformance() returns DriverReport[]|error {
    stream<DriverReport, sql:Error?> rs = dbClient->query(`
        SELECT driver_id AS driverId,
               MAX(driver_name) AS driverName,
               COUNT(*) AS assigned,
               COUNT(CASE WHEN status = 'DELIVERED' THEN 1 END) AS delivered,
               ROUND(AVG(CASE WHEN assigned_at IS NOT NULL AND delivered_at IS NOT NULL
                              THEN TIMESTAMPDIFF(MINUTE, assigned_at, delivered_at) END), 1) AS averageMinutes
        FROM rpt_deliveries
        WHERE driver_id IS NOT NULL
        GROUP BY driver_id
        ORDER BY delivered DESC, assigned DESC`);
    return from DriverReport r in rs
        select r;
}

function deliveriesByStatus() returns DeliveryStatusCount[]|error {
    stream<DeliveryStatusCount, sql:Error?> rs = dbClient->query(`
        SELECT status, COUNT(*) AS deliveries
        FROM rpt_deliveries
        GROUP BY status
        ORDER BY deliveries DESC`);
    return from DeliveryStatusCount r in rs
        select r;
}


function recentLowStock(int max) returns LowStockEntry[]|error {
    stream<LowStockEntry, sql:Error?> rs = dbClient->query(`
        SELECT restaurant_id AS restaurantId, menu_item_id AS menuItemId, item_name AS itemName,
               stock_quantity AS stockQuantity,
               DATE_FORMAT(occurred_at, '%Y-%m-%dT%H:%i:%sZ') AS occurredAt
        FROM rpt_low_stock
        ORDER BY occurred_at DESC, id DESC
        LIMIT ${max}`);
    return from LowStockEntry r in rs
        select r;
}

function listOrders(string? status, int? restaurantId, int? customerId, int pageSize, int offset)
        returns OrderRow[]|error {
    sql:ParameterizedQuery q = `
        SELECT order_id AS orderId, customer_id AS customerId, restaurant_id AS restaurantId,
               total_amount AS totalAmount, status, payment_status AS paymentStatus,
               reject_reason AS rejectReason,
               DATE_FORMAT(created_at, '%Y-%m-%dT%H:%i:%sZ') AS createdAt,
               DATE_FORMAT(updated_at, '%Y-%m-%dT%H:%i:%sZ') AS updatedAt,
               DATE_FORMAT(delivered_at, '%Y-%m-%dT%H:%i:%sZ') AS deliveredAt
        FROM rpt_orders WHERE 1=1`;
    if status is string {
        q = sql:queryConcat(q, ` AND status = ${status}`);
    }
    if restaurantId is int {
        q = sql:queryConcat(q, ` AND restaurant_id = ${restaurantId}`);
    }
    if customerId is int {
        q = sql:queryConcat(q, ` AND customer_id = ${customerId}`);
    }
    q = sql:queryConcat(q, ` ORDER BY created_at DESC, order_id LIMIT ${pageSize} OFFSET ${offset}`);
    stream<OrderRow, sql:Error?> rs = dbClient->query(q);
    return from OrderRow r in rs
        select r;
}
