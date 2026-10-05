import ballerina/http;

// Validation and the shared HTTP error responses.

final readonly & string[] RECIPIENT_TYPES = [CUSTOMER, DRIVER, RESTAURANT];

function validateManual(ManualNotification n) returns string? {
    if RECIPIENT_TYPES.indexOf(n.recipientType.trim().toUpperAscii()) is () {
        return "recipientType must be CUSTOMER, DRIVER or RESTAURANT";
    }
    if n.recipientId < 1 {
        return "recipientId must be positive";
    }
    if n.title.trim().length() == 0 || n.title.length() > 120 {
        return "title is required (max 120 characters)";
    }
    if n.message.trim().length() == 0 || n.message.length() > 500 {
        return "message is required (max 500 characters)";
    }
    return;
}

function validatePaging(int page, int pageSize) returns string? {
    if page < 1 {
        return "page must be >= 1";
    }
    if pageSize < 1 || pageSize > 100 {
        return "pageSize must be between 1 and 100";
    }
    return;
}

// HTTP response helpers
function badRequest(string message) returns http:BadRequest => {body: {code: "BAD_REQUEST", message}};

function notFound(string message) returns http:NotFound => {body: {code: "NOT_FOUND", message}};

function internalError() returns http:InternalServerError =>
    {body: {code: "INTERNAL_ERROR", message: "An unexpected error occurred"}};
