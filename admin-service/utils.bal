import ballerina/http;

// HTTP response helpers, same error body as the other services: {code, message}

function badRequest(string message) returns http:BadRequest => {body: {code: "BAD_REQUEST", message}};

function internalError() returns http:InternalServerError =>
    {body: {code: "INTERNAL_ERROR", message: "An unexpected error occurred"}};

final readonly & string[] ORDER_STATUSES = [
    "CREATED", "CONFIRMED", "PREPARING", "READY",
    "OUT_FOR_DELIVERY", "DELIVERED", "CANCELLED"
];

function validatePaging(int page, int pageSize) returns string? {
    if page < 1 {
        return "page must be >= 1";
    }
    if pageSize < 1 || pageSize > 100 {
        return "pageSize must be between 1 and 100";
    }
    return;
}

// "top N" style parameters: keeps somebody from asking for the top 5 million restaurants
function validateLimit(int 'limit) returns string? {
    if 'limit < 1 || 'limit > 100 {
        return "limit must be between 1 and 100";
    }
    return;
}

// Average order value. Kept apart from the SQL so it can be unit tested without a database.
function averageOf(decimal total, int count) returns decimal {
    if count <= 0 {
        return 0d;
    }
    return (total / <decimal>count).round(2);
}
