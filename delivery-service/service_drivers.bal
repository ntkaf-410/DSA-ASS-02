import ballerina/http;
import ballerina/log;
import ballerina/sql;

// REST API of the Delivery Service, driver side. Base path /drivers, port 8085.

listener http:Listener httpListener = new (servicePort);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
        allowHeaders: ["Content-Type", "Authorization"]
    }
}
service /drivers on httpListener {

    // New drivers start OFFLINE, they go on shift with PUT /drivers/{id}/status
    resource function post .(@http:Payload DriverInput payload)
            returns http:Created|http:BadRequest|http:Conflict|http:InternalServerError {
        string? invalid = validateDriver(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        int|error newId = insertDriver(payload);
        if newId is error {
            if isDuplicateKey(newId) {
                return conflictResponse("A driver with this phone number already exists");
            }
            log:printError("Driver insert failed", newId);
            return internalError();
        }
        Driver|sql:Error created = getDriver(newId);
        if created is sql:Error {
            log:printError("Could not load created driver", created, driverId = newId);
            return internalError();
        }
        return <http:Created>{
            headers: {"Location": string `/drivers/${newId}`},
            body: created
        };
    }

    // Optional ?status=AVAILABLE|BUSY|OFFLINE, handy for the admin view of who is on shift
    resource function get .(string? status) returns Driver[]|http:BadRequest|http:InternalServerError {
        string? wanted = status is string ? status.trim().toUpperAscii() : ();
        if wanted is string && DRIVER_STATUSES.indexOf(wanted) is () {
            return badRequest("status must be OFFLINE, AVAILABLE or BUSY");
        }
        Driver[]|error list = listDrivers(wanted);
        if list is error {
            log:printError("Listing drivers failed", list);
            return internalError();
        }
        return list;
    }

    resource function get [int id]() returns Driver|http:NotFound|http:InternalServerError {
        Driver|sql:Error driver = getDriver(id);
        if driver is sql:NoRowsError {
            return notFound(string `Driver ${id} not found`);
        }
        if driver is sql:Error {
            log:printError("Driver lookup failed", driver, driverId = id);
            return internalError();
        }
        return driver;
    }

    // Driver goes on or off shift. Coming online immediately checks the queue,
    // so an order that was waiting for a driver gets picked up right here.
    resource function put [int id]/status(@http:Payload DriverStatusUpdate payload)
            returns Driver|http:BadRequest|http:NotFound|http:Conflict|http:InternalServerError {
        string wanted = payload.status.trim().toUpperAscii();
        if wanted != DRIVER_AVAILABLE && wanted != DRIVER_OFFLINE {
            return badRequest("status must be AVAILABLE or OFFLINE");
        }
        Driver|sql:Error current = getDriver(id);
        if current is sql:NoRowsError {
            return notFound(string `Driver ${id} not found`);
        }
        if current is sql:Error {
            log:printError("Driver lookup failed", current, driverId = id);
            return internalError();
        }
        boolean|error changed = setDriverAvailability(id, wanted);
        if changed is error {
            log:printError("Driver status update failed", changed, driverId = id);
            return internalError();
        }
        if !changed {
            return conflictResponse("Driver is on a delivery, finish it before changing status");
        }
        if wanted == DRIVER_AVAILABLE {
            assignWaitingDeliveries();
        }
        // read it back: the queue check above may already have made this driver BUSY
        Driver|sql:Error updated = getDriver(id);
        if updated is sql:Error {
            log:printError("Could not reload driver", updated, driverId = id);
            return internalError();
        }
        return updated;
    }

    // GPS ping from the driver app, sent every few seconds while on shift
    resource function put [int id]/location(@http:Payload LocationUpdate payload)
            returns Driver|http:BadRequest|http:NotFound|http:InternalServerError {
        string? invalid = validateLocation(payload);
        if invalid is string {
            return badRequest(invalid);
        }
        Driver|error updated = recordDriverLocation(id, payload);
        if updated is sql:NoRowsError {
            return notFound(string `Driver ${id} not found`);
        }
        if updated is error {
            log:printError("Location update failed", updated, driverId = id);
            return internalError();
        }
        return updated;
    }

    // The driver's own jobs, newest first. ?status=ASSIGNED gives the driver app its current pickup.
    resource function get [int id]/deliveries(string? status, int page = 1, int pageSize = 20)
            returns Delivery[]|http:BadRequest|http:NotFound|http:InternalServerError {
        string? invalid = validatePaging(page, pageSize);
        if invalid is string {
            return badRequest(invalid);
        }
        Driver|sql:Error driver = getDriver(id);
        if driver is sql:NoRowsError {
            return notFound(string `Driver ${id} not found`);
        }
        if driver is sql:Error {
            log:printError("Driver lookup failed", driver, driverId = id);
            return internalError();
        }
        string? wanted = status is string ? status.trim().toUpperAscii() : ();
        Delivery[]|error list = listDeliveries(wanted, id, pageSize, (page - 1) * pageSize);
        if list is error {
            log:printError("Listing driver deliveries failed", list, driverId = id);
            return internalError();
        }
        return list;
    }
}

// Used by the Docker healthcheck and by the admin/infra side
service /health on httpListener {
    resource function get .() returns json|http:ServiceUnavailable {
        int|error ping = dbClient->queryRow(`SELECT 1`);
        if ping is error {
            return <http:ServiceUnavailable>{body: {"status": "DOWN", "service": "delivery-service"}};
        }
        return {"status": "UP", "service": "delivery-service"};
    }
}
