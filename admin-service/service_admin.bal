import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerina/time;

// REST API of the Admin Service. Base path /admin, port 8087.
// Read only: reports come from our own read model (see db.bal), nothing here changes
// an order, a payment or a delivery.

listener http:Listener httpListener = new (servicePort);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /admin on httpListener {

    // The numbers for the top of the dashboard, all in one call
    resource function get reports/summary() returns SummaryReport|http:InternalServerError {
        OrderTotalsRow|sql:Error totals = orderTotals();
        int|sql:Error customers = countCustomers();
        int|sql:Error deliveries = countCompletedDeliveries();
        if totals is sql:Error || customers is sql:Error || deliveries is sql:Error {
            log:printError("Summary report failed");
            return internalError();
        }
        return {
            totalOrders: totals.totalOrders,
            activeOrders: totals.activeOrders,
            deliveredOrders: totals.deliveredOrders,
            cancelledOrders: totals.cancelledOrders,
            paidOrders: totals.paidOrders,
            grossRevenue: totals.grossRevenue,
            averageOrderValue: averageOf(totals.grossRevenue, totals.paidOrders),
            averageDeliveryMinutes: totals.averageDeliveryMinutes,
            customers,
            deliveriesCompleted: deliveries,
            generatedAt: time:utcToString(time:utcNow())
        };
    }

    // How many orders sit in each status right now
    resource function get reports/orders/status() returns StatusCount[]|http:InternalServerError {
        StatusCount[]|error rows = ordersByStatus();
        if rows is error {
            log:printError("Orders-by-status report failed", rows);
            return internalError();
        }
        return rows;
    }

    // Orders and revenue per day, ?days=30 by default (max one year)
    resource function get reports/revenue/daily(int days = 30)
            returns DailyRevenue[]|http:BadRequest|http:InternalServerError {
        if days < 1 || days > 365 {
            return badRequest("days must be between 1 and 365");
        }
        DailyRevenue[]|error rows = dailyRevenue(days);
        if rows is error {
            log:printError("Daily revenue report failed", rows);
            return internalError();
        }
        return rows;
    }

    // Best earning restaurants first
    resource function get reports/restaurants(int 'limit = 10)
            returns RestaurantReport[]|http:BadRequest|http:InternalServerError {
        string? invalid = validateLimit('limit);
        if invalid is string {
            return badRequest(invalid);
        }
        RestaurantReport[]|error rows = topRestaurants('limit);
        if rows is error {
            log:printError("Restaurant report failed", rows);
            return internalError();
        }
        return rows;
    }

    // Biggest spenders first
    resource function get reports/customers(int 'limit = 10)
            returns CustomerReport[]|http:BadRequest|http:InternalServerError {
        string? invalid = validateLimit('limit);
        if invalid is string {
            return badRequest(invalid);
        }
        CustomerReport[]|error rows = topCustomers('limit);
        if rows is error {
            log:printError("Customer report failed", rows);
            return internalError();
        }
        return rows;
    }

    // Jobs per driver and how long they take from assignment to drop-off
    resource function get reports/drivers() returns DriverReport[]|http:InternalServerError {
        DriverReport[]|error rows = driverPerformance();
        if rows is error {
            log:printError("Driver report failed", rows);
            return internalError();
        }
        return rows;
    }

    resource function get reports/deliveries() returns DeliveryStatusCount[]|http:InternalServerError {
        DeliveryStatusCount[]|error rows = deliveriesByStatus();
        if rows is error {
            log:printError("Delivery report failed", rows);
            return internalError();
        }
        return rows;
    }


    // Latest low-stock warnings from the restaurants
    resource function get reports/stock(int 'limit = 20)
            returns LowStockEntry[]|http:BadRequest|http:InternalServerError {
        string? invalid = validateLimit('limit);
        if invalid is string {
            return badRequest(invalid);
        }
        LowStockEntry[]|error rows = recentLowStock('limit);
        if rows is error {
            log:printError("Low stock report failed", rows);
            return internalError();
        }
        return rows;
    }

    // Every order on the platform, newest first. Filters: ?status= ?restaurantId= ?customerId=
    resource function get orders(string? status, int? restaurantId, int? customerId, int page = 1, int pageSize = 20)
            returns OrderRow[]|http:BadRequest|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        string? wanted = status is string ? status.trim().toUpperAscii() : ();
        if wanted is string && ORDER_STATUSES.indexOf(wanted) is () {
            return badRequest("unknown order status " + wanted);
        }
        OrderRow[]|error rows = listOrders(wanted, restaurantId, customerId, pageSize, (page - 1) * pageSize);
        if rows is error {
            log:printError("Listing orders failed", rows);
            return internalError();
        }
        return rows;
    }

    // Is everything up? Always answers 200, the per-service status is in the body,
    // because "payment-service is down" is a valid answer and not an error of this endpoint.
    resource function get services() returns ServiceHealth[] {
        return checkServices();
    }
}

// Used by the Docker healthcheck
service /health on httpListener {
    resource function get .() returns json|http:ServiceUnavailable {
        int|error ping = dbClient->queryRow(`SELECT 1`);
        if ping is error {
            return <http:ServiceUnavailable>{body: {"status": "DOWN", "service": "admin-service"}};
        }
        return {"status": "UP", "service": "admin-service"};
    }
}
