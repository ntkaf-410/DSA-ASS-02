function paymentStatus(decimal amount, boolean forceFailure) returns string {
    if forceFailure || amount <= 0d {
        return "FAILED";
    }
    return "COMPLETED";
}
