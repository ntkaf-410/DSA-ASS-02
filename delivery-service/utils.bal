import ballerina/http;
import ballerina/lang.regexp;
import ballerina/sql;
import ballerina/time;

// Validation, small helpers and the shared HTTP error responses.

final regexp:RegExp PHONE_PATTERN = re `\+?[0-9]{7,15}`;

final readonly & string[] DELIVERY_STATUSES = [
    PENDING, AWAITING_DRIVER, ASSIGNED, OUT_FOR_DELIVERY, DELIVERED, CANCELLED
];

final readonly & string[] DRIVER_STATUSES = [DRIVER_OFFLINE, DRIVER_AVAILABLE, DRIVER_BUSY];

// Validation (returns a message, or () when the input is fine)
function validateDriver(DriverInput d) returns string? {
    if d.fullName.trim().length() < 2 {
        return "fullName must be at least 2 characters";
    }
    if !regexp:isFullMatch(PHONE_PATTERN, d.phone.trim()) {
        return "phone must be 7-15 digits, optionally starting with +";
    }
    return;
}

function validateLocation(LocationUpdate l) returns string? {
    if l.latitude < -90d || l.latitude > 90d {
        return "latitude must be between -90 and 90";
    }
    if l.longitude < -180d || l.longitude > 180d {
        return "longitude must be between -180 and 180";
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

function nowIso() returns string {
    return time:utcToString(time:utcNow());
}

// DB error helper
// MySQL error 1062 = duplicate entry on a UNIQUE key (here: the driver's phone number)
function isDuplicateKey(error e) returns boolean {
    return e is sql:DatabaseError && e.detail().errorCode == 1062;
}

// HTTP response helpers
function badRequest(string message) returns http:BadRequest => {body: {code: "BAD_REQUEST", message}};

function notFound(string message) returns http:NotFound => {body: {code: "NOT_FOUND", message}};

function conflictResponse(string message) returns http:Conflict => {body: {code: "CONFLICT", message}};

function internalError() returns http:InternalServerError =>
    {body: {code: "INTERNAL_ERROR", message: "An unexpected error occurred"}};
