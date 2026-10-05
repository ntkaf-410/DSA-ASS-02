import ballerina/crypto;
import ballerina/http;
import ballerina/lang.regexp;
import ballerina/sql;

// utils.bal - validation, password hashing and HTTP response helpers.
final regexp:RegExp EMAIL_PATTERN = re `[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}`;
final regexp:RegExp PHONE_PATTERN = re `\+?[0-9]{7,15}`;

final readonly & string[] VALID_STATUSES = [
    "CREATED", "CONFIRMED", "PREPARING", "READY",
    "OUT_FOR_DELIVERY", "DELIVERED", "CANCELLED"
];

//Validation (return an error message, or () when valid)
function validateRegistration(CustomerRegistration r) returns string? {
    if r.fullName.trim().length() < 2 {
        return "fullName must be at least 2 characters";
    }
    if !regexp:isFullMatch(EMAIL_PATTERN, r.email.trim()) {
        return "email is not a valid email address";
    }
    if !regexp:isFullMatch(PHONE_PATTERN, r.phone.trim()) {
        return "phone must be 7-15 digits, optionally starting with +";
    }
    if r.password.length() < 8 {
        return "password must be at least 8 characters";
    }
    return;
}

function validateUpdate(CustomerUpdate r) returns string? {
    if r.fullName.trim().length() < 2 {
        return "fullName must be at least 2 characters";
    }
    if !regexp:isFullMatch(PHONE_PATTERN, r.phone.trim()) {
        return "phone must be 7-15 digits, optionally starting with +";
    }
    return;
}

function validateAddress(AddressInput a) returns string? {
    if a.label.trim().length() == 0 {
        return "label is required";
    }
    if a.street.trim().length() == 0 {
        return "street is required";
    }
    if a.city.trim().length() == 0 {
        return "city is required";
    }
    decimal? lat = a.latitude;
    if lat is decimal && (lat < -90d || lat > 90d) {
        return "latitude must be between -90 and 90";
    }
    decimal? lng = a.longitude;
    if lng is decimal && (lng < -180d || lng > 180d) {
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

// Passwords (bcrypt, salted, work factor 12)
function hashPassword(string password) returns string|error {
    return crypto:hashBcrypt(password, 12);
}

function verifyPassword(string password, string hash) returns boolean|error {
    return crypto:verifyBcrypt(password, hash);
}

// DB error helpers
# MySQL error 1062 = duplicate entry for a UNIQUE key (e.g. e-mail).
function isDuplicateKey(error e) returns boolean {
    return e is sql:DatabaseError && e.detail().errorCode == 1062;
}

// HTTP response helpers
function badRequest(string message) returns http:BadRequest => {body: {code: "BAD_REQUEST", message}};

function notFound(string message) returns http:NotFound => {body: {code: "NOT_FOUND", message}};

function conflictResponse(string message) returns http:Conflict {
    return {body: {code: "CONFLICT", message}};
}

function unauthorized(string message) returns http:Unauthorized => {body: {code: "UNAUTHORIZED", message}};

function internalError() returns http:InternalServerError =>
    {body: {code: "INTERNAL_ERROR", message: "An unexpected error occurred"}};
