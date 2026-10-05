import ballerina/test;

// NOTE: module-level clients (MySQL/Kafka) initialise when tests run, so start
// the dev stack first:  docker compose -f docker-compose.dev.yml up -d mysql kafka

@test:Config {}
function testValidRegistrationPasses() {
    CustomerRegistration r = {
        fullName: "Ndapanda Shikongo",
        email: "ndapanda@example.com",
        phone: "+264811234567",
        password: "Secret123"
    };
    test:assertEquals(validateRegistration(r), ());
}

@test:Config {}
function testBadEmailRejected() {
    CustomerRegistration r = {fullName: "Test User", email: "not-an-email", phone: "0811234567", password: "Secret123"};
    test:assertEquals(validateRegistration(r), "email is not a valid email address");
}

@test:Config {}
function testShortPasswordRejected() {
    CustomerRegistration r = {fullName: "Test User", email: "a@b.com", phone: "0811234567", password: "short"};
    test:assertEquals(validateRegistration(r), "password must be at least 8 characters");
}

@test:Config {}
function testBadPhoneRejected() {
    CustomerUpdate u = {fullName: "Test User", phone: "abc"};
    test:assertTrue(validateUpdate(u) is string);
}

@test:Config {}
function testAddressLatitudeRange() {
    AddressInput a = {label: "Home", street: "1 Independence Ave", city: "Windhoek", latitude: 120.0d};
    test:assertEquals(validateAddress(a), "latitude must be between -90 and 90");
}

@test:Config {}
function testPagingBounds() {
    test:assertTrue(validatePaging(0, 20) is string);
    test:assertTrue(validatePaging(1, 500) is string);
    test:assertEquals(validatePaging(1, 20), ());
}

@test:Config {}
function testPasswordHashRoundTrip() returns error? {
    string hash = check hashPassword("Secret123");
    test:assertTrue(check verifyPassword("Secret123", hash));
    test:assertFalse(check verifyPassword("Wrong-pass", hash));
}
