import ballerina/http;
import ballerina/time;

// Health checks of the other services for GET /admin/services.
// Short timeout on purpose: a dead service should show up as DOWN quickly, not hang the page.

final http:Client customerHealth = check new (customerServiceUrl, timeout = healthTimeoutSeconds);
final http:Client restaurantHealth = check new (restaurantServiceUrl, timeout = healthTimeoutSeconds);
final http:Client orderHealth = check new (orderServiceUrl, timeout = healthTimeoutSeconds);
final http:Client paymentHealth = check new (paymentServiceUrl, timeout = healthTimeoutSeconds);
final http:Client deliveryHealth = check new (deliveryServiceUrl, timeout = healthTimeoutSeconds);
final http:Client notificationHealth = check new (notificationServiceUrl, timeout = healthTimeoutSeconds);

function probe(string name, string url, http:Client target) returns ServiceHealth {
    time:Utc started = time:utcNow();
    http:Response|error res = target->get("/health");
    int latencyMs = <int>(time:utcDiffSeconds(time:utcNow(), started) * 1000d);
    if res is error {
        return {name, url, status: "DOWN", httpStatus: (), latencyMs, detail: res.message()};
    }
    return {
        name,
        url,
        status: res.statusCode == 200 ? "UP" : "DOWN",
        httpStatus: res.statusCode,
        latencyMs,
        detail: ()
    };
}

// All six are pinged at the same time, otherwise two services being down would already
// cost two full timeouts before the admin sees anything.
function checkServices() returns ServiceHealth[] {
    future<ServiceHealth> customer = start probe("customer-service", customerServiceUrl, customerHealth);
    future<ServiceHealth> restaurant = start probe("restaurant-service", restaurantServiceUrl, restaurantHealth);
    future<ServiceHealth> 'order = start probe("order-service", orderServiceUrl, orderHealth);
    future<ServiceHealth> payment = start probe("payment-service", paymentServiceUrl, paymentHealth);
    future<ServiceHealth> delivery = start probe("delivery-service", deliveryServiceUrl, deliveryHealth);
    future<ServiceHealth> notification = start probe("notification-service", notificationServiceUrl,
        notificationHealth);

    ServiceHealth[] results = [];
    foreach future<ServiceHealth> f in [customer, restaurant, 'order, payment, delivery, notification] {
        ServiceHealth|error r = wait f;
        if r is ServiceHealth {
            results.push(r);
        }
    }
    return results;
}
