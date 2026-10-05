import ballerina/http;

final http:Client customerClient = check new (customerServiceUrl, timeout = 5);
final http:Client restaurantClient = check new (restaurantServiceUrl, timeout = 5);

// Tolerant (open) views of Person 2's RestaurantStatus and MenuItem: extra fields are ignored.
type RestaurantStatusView record {
    boolean isActive;
    boolean isOpen;
    boolean acceptingOrders;
};

type MenuItemView record {
    int id;
    string name;
    decimal price;
    boolean isAvailable;
};

// Person 1 contract: 200 = valid, 404 = invalid customer or address.
public function addressExists(int customerId, int addressId) returns boolean|error {
    http:Response r = check customerClient->get(string `/customers/${customerId}/addresses/${addressId}`);
    if r.statusCode == 200 {
        return true;
    }
    if r.statusCode == 404 {
        return false;
    }
    return error(string `customer-service returned ${r.statusCode}`);
}

// ASSUMPTION: GET /restaurants/{id}/status returns Person 2's RestaurantStatus. Adjust path if different.
// Returns "OK", "NOT_FOUND" or "NOT_ACCEPTING".
public function checkRestaurant(int restaurantId) returns string|error {
    http:Response r = check restaurantClient->get(string `/restaurants/${restaurantId}/status`);
    if r.statusCode == 404 {
        return "NOT_FOUND";
    }
    if r.statusCode != 200 {
        return error(string `restaurant-service returned ${r.statusCode}`);
    }
    RestaurantStatusView st = check (check r.getJsonPayload()).fromJsonWithType();
    return st.isActive && st.isOpen && st.acceptingOrders ? "OK" : "NOT_ACCEPTING";
}

// ASSUMPTION: GET /restaurants/{id}/menu returns a JSON array of MenuItem. Adjust path if different.
public function fetchMenu(int restaurantId) returns MenuItemView[]|error {
    http:Response r = check restaurantClient->get(string `/restaurants/${restaurantId}/menu`);
    if r.statusCode != 200 {
        return error(string `restaurant-service returned ${r.statusCode}`);
    }
    return check (check r.getJsonPayload()).fromJsonWithType();
}
