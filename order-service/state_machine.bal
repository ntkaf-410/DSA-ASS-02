final map<string[]> TRANSITIONS = {
    "CREATED": [CONFIRMED, CANCELLED],
    "CONFIRMED": [PREPARING, CANCELLED],
    "PREPARING": [READY],
    "READY": [OUT_FOR_DELIVERY],
    "OUT_FOR_DELIVERY": [DELIVERED],
    "DELIVERED": [],
    "CANCELLED": []
};

public function isValidStatus(string s) returns boolean {
    return TRANSITIONS.hasKey(s);
}

public function canTransition(string current, string next) returns boolean {
    string[]? allowed = TRANSITIONS[current];
    if allowed is () {
        return false;
    }
    return allowed.indexOf(next) is int;
}
