import ballerina/test;

// Unit tests for validation, opening hours and event parsing.
// The module's init() connects to MySQL, so start the DB before `bal test`.

function sampleRestaurant() returns RestaurantInput => {
    name: "Kalahari Grill",
    cuisine: "Braai",
    phone: "+264611234567",
    address: "12 Independence Ave",
    city: "Windhoek"
};

function weekdayHours() returns OpeningHours[] => [
    {dayOfWeek: 1, isClosed: false, openTime: "08:00", closeTime: "17:00"},
    {dayOfWeek: 2, isClosed: false, openTime: "18:00", closeTime: "02:00"},
    {dayOfWeek: 0, isClosed: true, openTime: (), closeTime: ()}
];

@test:Config {}
function validRestaurantPasses() {
    test:assertEquals(validateRestaurant(sampleRestaurant()), ());
}

@test:Config {}
function badPhoneIsRejected() {
    RestaurantInput r = sampleRestaurant();
    r.phone = "abc";
    test:assertTrue(validateRestaurant(r) is string);
}

@test:Config {}
function latitudeOutOfRangeIsRejected() {
    RestaurantInput r = sampleRestaurant();
    r.latitude = 120d;
    test:assertTrue(validateRestaurant(r) is string);
}

@test:Config {}
function menuItemNeedsPositivePrice() {
    MenuItemInput m = {name: "Steak", category: "Mains", price: 0d};
    test:assertTrue(validateMenuItem(m) is string);
}

@test:Config {}
function menuItemRejectsNegativeStock() {
    MenuItemInput m = {name: "Steak", category: "Mains", price: 95d, stockQuantity: -1};
    test:assertTrue(validateMenuItem(m) is string);
}

@test:Config {}
function hoursRejectDuplicateDay() {
    OpeningHoursInput[] h = [
        {dayOfWeek: 1, openTime: "08:00", closeTime: "17:00"},
        {dayOfWeek: 1, openTime: "09:00", closeTime: "18:00"}
    ];
    test:assertTrue(validateHours(h) is string);
}

@test:Config {}
function hoursRejectBadTime() {
    OpeningHoursInput[] h = [{dayOfWeek: 1, openTime: "25:00", closeTime: "17:00"}];
    test:assertTrue(validateHours(h) is string);
}

@test:Config {}
function closedDayNeedsNoTimes() {
    OpeningHoursInput[] h = [{dayOfWeek: 0, isClosed: true}];
    test:assertEquals(validateHours(h), ());
}

@test:Config {}
function minutesAreParsed() {
    test:assertEquals(toMinutes("08:30"), 510);
    test:assertEquals(toMinutes("nope"), -1);
}

@test:Config {}
function openDuringNormalHours() {
    test:assertTrue(isOpenAt(weekdayHours(), 1, 12 * 60));
}

@test:Config {}
function closedBeforeOpening() {
    test:assertFalse(isOpenAt(weekdayHours(), 1, 7 * 60));
}

@test:Config {}
function closeTimeItselfIsClosed() {
    test:assertFalse(isOpenAt(weekdayHours(), 1, 17 * 60));
}

@test:Config {}
function overnightHoursWork() {
    test:assertTrue(isOpenAt(weekdayHours(), 2, 23 * 60));
    test:assertTrue(isOpenAt(weekdayHours(), 2, 60));
    test:assertFalse(isOpenAt(weekdayHours(), 2, 10 * 60));
}

@test:Config {}
function closedDayIsClosed() {
    test:assertFalse(isOpenAt(weekdayHours(), 0, 12 * 60));
}

@test:Config {}
function dayWithNoHoursIsClosed() {
    test:assertFalse(isOpenAt(weekdayHours(), 5, 12 * 60));
}

@test:Config {}
function noHoursConfiguredMeansOpen() {
    test:assertTrue(isOpenNow([]));
}

@test:Config {}
function orderEventAcceptsStringAndNumberIds() returns error? {
    json payload = {orderId: "ord-1", customerId: 3, restaurantId: "2",
        items: [{menuItemId: 5, quantity: 1}]};
    OrderRequest req = check parseOrderCreated(payload);
    test:assertEquals(req.restaurantId, 2);
    test:assertEquals(req.customerId, 3);
}

@test:Config {}
function orderEventMergesRepeatedItems() returns error? {
    json payload = {orderId: "ord-2", restaurantId: 2,
        items: [{menuItemId: 5, quantity: 1}, {menuItemId: 6, quantity: 1}, {menuItemId: 5, quantity: 2}]};
    OrderRequest req = check parseOrderCreated(payload);
    test:assertEquals(req.lines.length(), 2);
    test:assertEquals(req.lines[0].menuItemId, 5);
    test:assertEquals(req.lines[0].quantity, 3);
}

@test:Config {}
function orderEventWithoutItemsFails() {
    json payload = {orderId: "ord-3", restaurantId: 2, items: []};
    OrderRequest|error req = parseOrderCreated(payload);
    test:assertTrue(req is error);
}

@test:Config {}
function orderEventWithZeroQuantityFails() {
    json payload = {orderId: "ord-4", restaurantId: 2, items: [{menuItemId: 5, quantity: 0}]};
    OrderRequest|error req = parseOrderCreated(payload);
    test:assertTrue(req is error);
}

@test:Config {}
function kitchenOnlyMovesForward() {
    test:assertEquals(NEXT_STATUS["CONFIRMED"], "PREPARING");
    test:assertEquals(NEXT_STATUS["PREPARING"], "READY");
    test:assertEquals(NEXT_STATUS["READY"], ());
}
