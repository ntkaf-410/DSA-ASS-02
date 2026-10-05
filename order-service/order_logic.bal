public function applyTransition(string orderId, string next, string actor) returns OrderRecord|error {
    OrderRecord? existing = check getOrder(orderId);
    if existing is () {
        return error OrderNotFound(string `order ${orderId} not found`);
    }
    if !canTransition(existing.status, next) {
        return error InvalidTransition(string `cannot move order from ${existing.status} to ${next}`);
    }
    boolean ok = check updateStatus(orderId, existing.status, next, actor);
    if !ok {
        return error ConflictError("order was modified concurrently, please retry");
    }
    publishStatusChanged(orderId, next);
    OrderRecord updated = existing.clone();
    updated.status = next;
    return updated;
}
