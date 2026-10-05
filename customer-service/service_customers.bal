import ballerina/http;
import ballerina/log;
import ballerina/sql;


// service_customers.bal - REST API of the Customer Service.
// Base path: /customers   (default port 8081)

listener http:Listener httpListener = new (servicePort);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /customers on httpListener {

    //ACCOUNTS
    # Register a new customer account.
    resource function post .(@http:Payload CustomerRegistration payload)
            returns http:Created|http:BadRequest|http:Conflict|http:InternalServerError {
        string? invalid = validateRegistration(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        string|error hash = hashPassword(payload.password);
        if hash is error {
            log:printError("Password hashing failed", hash);
            return internalError();
        }
        string email = payload.email.trim().toLowerAscii();
        int|error newId = insertCustomer(payload.fullName.trim(), email, payload.phone.trim(), hash);
        if newId is error {
            if isDuplicateKey(newId) {
                return conflictResponse("A customer with this email already exists");
            }
            log:printError("Customer insert failed", newId);
            return internalError();
        }
        Customer|sql:Error created = getCustomerById(newId);
        if created is sql:Error {
            log:printError("Could not load created customer", created, customerId = newId);
            return internalError();
        }
        publishCustomerRegistered(created);
        return <http:Created>{
            headers: {"Location": string `/customers/${newId}`},
            body: created
        };
    }

    # Verify credentials and return the customer profile.
    resource function post login(@http:Payload LoginRequest payload)
            returns Customer|http:Unauthorized|http:InternalServerError {
        CredentialRow|sql:Error cred = getCredentialsByEmail(payload.email.trim().toLowerAscii());
        if cred is sql:NoRowsError {
            return unauthorized("Invalid email or password");
        }
        if cred is sql:Error {
            log:printError("Login lookup failed", cred);
            return internalError();
        }
        boolean|error ok = verifyPassword(payload.password, cred.passwordHash);
        if ok is error {
            log:printError("Password verification failed", ok);
            return internalError();
        }
        if !ok {
            return unauthorized("Invalid email or password");
        }
        Customer|sql:Error c = getCustomerById(cred.id);
        if c is Customer {
            return c;
        }
        log:printError("Could not load customer after login", c);
        return internalError();
    }

    # List customers (paginated) - intended for the Admin Service.
    resource function get .(int page = 1, int pageSize = 20)
            returns Customer[]|http:BadRequest|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        Customer[]|error list = listCustomers(pageSize, (page - 1) * pageSize);
        if list is error {
            log:printError("Listing customers failed", list);
            return internalError();
        }
        return list;
    }

    resource function get [int id]() returns Customer|http:NotFound|http:InternalServerError {
        Customer|sql:Error c = getCustomerById(id);
        if c is Customer {
            return c;
        }
        if c is sql:NoRowsError {
            return notFound(string `Customer ${id} not found`);
        }
        log:printError("Customer lookup failed", c, customerId = id);
        return internalError();
    }

    resource function put [int id](@http:Payload CustomerUpdate payload)
            returns Customer|http:BadRequest|http:NotFound|http:InternalServerError {
        string? invalid = validateUpdate(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        error? updated = updateCustomer(id, payload.fullName.trim(), payload.phone.trim());
        if updated is error {
            log:printError("Customer update failed", updated, customerId = id);
            return internalError();
        }
        Customer|sql:Error c = getCustomerById(id);
        if c is Customer {
            return c;
        }
        if c is sql:NoRowsError {
            return notFound(string `Customer ${id} not found`);
        }
        return internalError();
    }

    resource function delete [int id]() returns http:NoContent|http:NotFound|http:InternalServerError {
        int|error rows = deleteCustomer(id);
        if rows is error {
            log:printError("Customer delete failed", rows, customerId = id);
            return internalError();
        }
        if rows == 0 {
            return notFound(string `Customer ${id} not found`);
        }
        return http:NO_CONTENT;
    }

    //DELIVERY ADDRESSES 

    resource function post [int id]/addresses(@http:Payload AddressInput payload)
            returns http:Created|http:BadRequest|http:NotFound|http:InternalServerError {
        http:NotFound|http:InternalServerError? guard = ensureCustomer(id);
        if guard !is () {
            return guard;
        }
        string? invalid = validateAddress(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        int|error addressId = insertAddress(id, payload);
        if addressId is error {
            log:printError("Address insert failed", addressId, customerId = id);
            return internalError();
        }
        Address|sql:Error a = getAddress(id, addressId);
        if a is sql:Error {
            return internalError();
        }
        return <http:Created>{
            headers: {"Location": string `/customers/${id}/addresses/${addressId}`},
            body: a
        };
    }

    resource function get [int id]/addresses()
            returns Address[]|http:NotFound|http:InternalServerError {
        http:NotFound|http:InternalServerError? guard = ensureCustomer(id);
        if guard !is () {
            return guard;
        }
        Address[]|error list = listAddresses(id);
        if list is error {
            log:printError("Listing addresses failed", list, customerId = id);
            return internalError();
        }
        return list;
    }

    # Also used by the Order Service to validate a delivery address.
    resource function get [int id]/addresses/[int addressId]()
            returns Address|http:NotFound|http:InternalServerError {
        Address|sql:Error a = getAddress(id, addressId);
        if a is Address {
            return a;
        }
        if a is sql:NoRowsError {
            return notFound(string `Address ${addressId} not found for customer ${id}`);
        }
        log:printError("Address lookup failed", a);
        return internalError();
    }

    resource function put [int id]/addresses/[int addressId](@http:Payload AddressInput payload)
            returns Address|http:BadRequest|http:NotFound|http:InternalServerError {
        string? invalid = validateAddress(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        error? updated = updateAddress(id, addressId, payload);
        if updated is error {
            log:printError("Address update failed", updated);
            return internalError();
        }
        Address|sql:Error a = getAddress(id, addressId);
        if a is Address {
            return a;
        }
        if a is sql:NoRowsError {
            return notFound(string `Address ${addressId} not found for customer ${id}`);
        }
        return internalError();
    }

    resource function put [int id]/addresses/[int addressId]/default()
            returns Address|http:NotFound|http:InternalServerError {
        boolean|error found = setDefaultAddress(id, addressId);
        if found is error {
            log:printError("Setting default address failed", found);
            return internalError();
        }
        if !found {
            return notFound(string `Address ${addressId} not found for customer ${id}`);
        }
        Address|sql:Error a = getAddress(id, addressId);
        if a is Address {
            return a;
        }
        return internalError();
    }

    resource function delete [int id]/addresses/[int addressId]()
            returns http:NoContent|http:NotFound|http:InternalServerError {
        int|error rows = deleteAddress(id, addressId);
        if rows is error {
            log:printError("Address delete failed", rows);
            return internalError();
        }
        if rows == 0 {
            return notFound(string `Address ${addressId} not found for customer ${id}`);
        }
        return http:NO_CONTENT;
    }

    //ORDER HISTORY

    # Paginated order history, newest first. Optional ?status=DELIVERED filter.
    resource function get [int id]/orders(string? status, int page = 1, int pageSize = 20)
            returns OrderSummary[]|http:BadRequest|http:NotFound|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        if status is string && VALID_STATUSES.indexOf(status.toUpperAscii()) is () {
            return badRequest(string `Unknown status '${status}'`);
        }
        http:NotFound|http:InternalServerError? guard = ensureCustomer(id);
        if guard !is () {
            return guard;
        }
        string? statusFilter = status is string ? status.toUpperAscii() : ();
        OrderSummary[]|error orders = listOrders(id, statusFilter, pageSize, (page - 1) * pageSize);
        if orders is error {
            log:printError("Listing order history failed", orders, customerId = id);
            return internalError();
        }
        return orders;
    }

    resource function get [int id]/orders/[string orderId]()
            returns OrderSummary|http:NotFound|http:InternalServerError {
        OrderSummary|error o = getOrder(id, orderId);
        if o is OrderSummary {
            return o;
        }
        if o is sql:NoRowsError {
            return notFound(string `Order ${orderId} not found for customer ${id}`);
        }
        log:printError("Order lookup failed", o);
        return internalError();
    }
}

# Liveness/readiness probe (used by Docker Compose healthcheck).
service /health on httpListener {
    resource function get .() returns json|http:ServiceUnavailable {
        int|error ping = dbClient->queryRow(`SELECT 1`);
        if ping is error {
            return <http:ServiceUnavailable>{body: {"status": "DOWN", "service": "customer-service"}};
        }
        return {"status": "UP", "service": "customer-service"};
    }
}

# Returns () when the customer exists, otherwise a ready-made error response.
function ensureCustomer(int id) returns http:NotFound|http:InternalServerError? {
    boolean|error exists = customerExists(id);
    if exists is error {
        log:printError("Customer existence check failed", exists, customerId = id);
        return internalError();
    }
    if !exists {
        return notFound(string `Customer ${id} not found`);
    }
    return;
}
