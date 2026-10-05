import ballerina/http;
import ballerina/lang.regexp;
import ballerina/sql;
import ballerina/time;

final regexp:RegExp PHONE_PATTERN = re `\+?[0-9]{7,15}`;
final regexp:RegExp TIME_PATTERN = re `([01][0-9]|2[0-3]):[0-5][0-9]`;

// The kitchen can only move an order forward one step at a time
final readonly & map<string> NEXT_STATUS = {
    "CONFIRMED": "PREPARING",
    "PREPARING": "READY"
};

// Validation helpers return an error message, or () when everything is fine

function validateRestaurant(RestaurantInput r) returns string? {
    if r.name.trim().length() < 2 {
        return "name must be at least 2 characters";
    }
    if r.cuisine.trim().length() == 0 {
        return "cuisine is required";
    }
    if !regexp:isFullMatch(PHONE_PATTERN, r.phone.trim()) {
        return "phone must be 7-15 digits, optionally starting with +";
    }
    if r.address.trim().length() == 0 {
        return "address is required";
    }
    if r.city.trim().length() == 0 {
        return "city is required";
    }
    decimal? lat = r.latitude;
    if lat is decimal && (lat < -90d || lat > 90d) {
        return "latitude must be between -90 and 90";
    }
    decimal? lng = r.longitude;
    if lng is decimal && (lng < -180d || lng > 180d) {
        return "longitude must be between -180 and 180";
    }
    return;
}

function validateMenuItem(MenuItemInput m) returns string? {
    if m.name.trim().length() == 0 {
        return "name is required";
    }
    if m.category.trim().length() == 0 {
        return "category is required";
    }
    if m.price <= 0d {
        return "price must be greater than 0";
    }
    int? stock = m.stockQuantity;
    if stock is int && stock < 0 {
        return "stockQuantity cannot be negative";
    }
    return;
}

function validateHours(OpeningHoursInput[] hours) returns string? {
    if hours.length() == 0 {
        return "at least one day is required";
    }
    map<boolean> seen = {};
    foreach OpeningHoursInput h in hours {
        if h.dayOfWeek < 0 || h.dayOfWeek > 6 {
            return "dayOfWeek must be between 0 (Sunday) and 6 (Saturday)";
        }
        string key = h.dayOfWeek.toString();
        if seen.hasKey(key) {
            return string `dayOfWeek ${h.dayOfWeek} appears more than once`;
        }
        seen[key] = true;

        boolean closed = h.isClosed ?: false;
        if closed {
            continue;
        }
        string? openAt = h.openTime;
        string? closeAt = h.closeTime;
        if openAt is () || closeAt is () {
            return "openTime and closeTime are required unless isClosed is true";
        }
        if !regexp:isFullMatch(TIME_PATTERN, openAt) || !regexp:isFullMatch(TIME_PATTERN, closeAt) {
            return "times must be HH:MM in 24h format";
        }
        if openAt == closeAt {
            return "openTime and closeTime cannot be the same";
        }
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

// Opening hours logic

// "08:30" -> 510. Returns -1 if the string is not a time.
function toMinutes(string t) returns int {
    string[] parts = regexp:split(re `:`, t.trim());
    if parts.length() != 2 {
        return -1;
    }
    int|error h = int:fromString(parts[0]);
    int|error m = int:fromString(parts[1]);
    if h is int && m is int {
        return h * 60 + m;
    }
    return -1;
}

// Is the restaurant open at this weekday/minute? (kept pure so it's easy to test)
function isOpenAt(OpeningHours[] hours, int dayOfWeek, int minuteOfDay) returns boolean {
    foreach OpeningHours h in hours {
        if h.dayOfWeek != dayOfWeek {
            continue;
        }
        string? openAt = h.openTime;
        string? closeAt = h.closeTime;
        if h.isClosed {
            return false;
        }
        if openAt is string && closeAt is string {
            int openMin = toMinutes(openAt);
            int closeMin = toMinutes(closeAt);
            if openMin < 0 || closeMin < 0 {
                return false;
            }
            if openMin < closeMin {
                return minuteOfDay >= openMin && minuteOfDay < closeMin;
            }
            // closes after midnight, e.g. 18:00 -> 02:00
            return minuteOfDay >= openMin || minuteOfDay < closeMin;
        }
        return false;
    }
    return false;
}

// Local weekday (0 = Sunday) and minute of day, using the configured UTC offset.
function localDayAndMinute() returns [int, int] {
    int local = time:utcNow()[0] + utcOffsetSeconds;
    int days = local / 86400;
    // 1 Jan 1970 was a Thursday
    return [(days + 4) % 7, (local % 86400) / 60];
}

// A restaurant with no hours configured is treated as always open.
function isOpenNow(OpeningHours[] hours) returns boolean {
    if hours.length() == 0 {
        return true;
    }
    var [dow, minute] = localDayAndMinute();
    return isOpenAt(hours, dow, minute);
}

// Event parsing. Done by hand so the service accepts "restaurantId": 2 as well as "2".

function toInt(json v) returns int|error {
    if v is int {
        return v;
    }
    if v is string {
        return int:fromString(v.trim());
    }
    if v is decimal {
        return <int>v;
    }
    if v is float {
        return <int>v;
    }
    return error("expected a number but got " + v.toString());
}

// Reads an orders.created payload. Lines for the same menu item are merged.
function parseOrderCreated(json payload) returns OrderRequest|error {
    json orderIdJson = check payload.orderId;
    string orderId = orderIdJson.toString();
    if orderId.trim().length() == 0 {
        return error("orderId is empty");
    }
    json restaurantJson = check payload.restaurantId;
    int restaurantId = check toInt(restaurantJson);

    int? customerId = ();
    json|error customerJson = payload.customerId;
    if customerJson is int|string {
        customerId = check toInt(customerJson);
    }

    json itemsJson = check payload.items;
    if itemsJson !is json[] || itemsJson.length() == 0 {
        return error("items must be a non-empty array");
    }

    map<int> totals = {};
    int[] itemOrder = [];
    foreach json entry in itemsJson {
        json idJson = check entry.menuItemId;
        json qtyJson = check entry.quantity;
        int itemId = check toInt(idJson);
        int qty = check toInt(qtyJson);
        if qty < 1 {
            return error(string `quantity for item ${itemId} must be at least 1`);
        }
        string key = itemId.toString();
        int? soFar = totals[key];
        if soFar is () {
            itemOrder.push(itemId);
            totals[key] = qty;
        } else {
            totals[key] = soFar + qty;
        }
    }
    OrderLine[] lines = from int i in itemOrder
        select {menuItemId: i, quantity: totals.get(i.toString())};
    return {orderId, customerId, restaurantId, lines};
}

// DB error helper
// MySQL error 1062 = duplicate entry on a UNIQUE key
function isDuplicateKey(error e) returns boolean {
    return e is sql:DatabaseError && e.detail().errorCode == 1062;
}

// HTTP response helpers
function badRequest(string message) returns http:BadRequest => {body: {code: "BAD_REQUEST", message}};

function notFound(string message) returns http:NotFound => {body: {code: "NOT_FOUND", message}};

function conflictResponse(string message) returns http:Conflict => {body: {code: "CONFLICT", message}};

function internalError() returns http:InternalServerError =>
    {body: {code: "INTERNAL_ERROR", message: "An unexpected error occurred"}};
