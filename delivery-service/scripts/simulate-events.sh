#!/usr/bin/env bash
# Plays the Order Service so the delivery flow can be tried without the rest of the platform.
#
#   ./scripts/simulate-events.sh order-1 created     # order placed -> delivery opened (PENDING)
#   ./scripts/simulate-events.sh order-1 ready       # kitchen done -> driver gets assigned
#   ./scripts/simulate-events.sh order-1 cancelled   # order cancelled -> delivery cancelled, driver freed
#   ./scripts/simulate-events.sh order-1 watch       # print what we published for the deliveries.* topics
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <order-id> created|ready|cancelled|watch" >&2
  exit 2
fi

ORDER_ID="$1"
WHAT="$2"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"
BOOTSTRAP="${BOOTSTRAP:-kafka:19092}"

send() { # topic payload
  printf '%s:%s\n' "$ORDER_ID" "$2" | docker compose -f docker-compose.dev.yml exec -T "$KAFKA_CONTAINER" \
    /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server "$BOOTSTRAP" \
    --topic "$1" --property parse.key=true --property key.separator=:
}

case "$WHAT" in
  created)
    send orders.created "{\"orderId\":\"$ORDER_ID\",\"customerId\":1,\"restaurantId\":1,\"totalAmount\":185.50,\"deliveryAddressId\":1,\"items\":[]}" ;;
  ready)
    send orders.status.changed "{\"orderId\":\"$ORDER_ID\",\"status\":\"READY\"}" ;;
  cancelled)
    send orders.status.changed "{\"orderId\":\"$ORDER_ID\",\"status\":\"CANCELLED\"}" ;;
  watch)
    # the three topics start with the same prefix, so one regex subscription covers them
    docker compose -f docker-compose.dev.yml exec -T "$KAFKA_CONTAINER" \
      /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server "$BOOTSTRAP" \
      --include 'deliveries\..*' --from-beginning --property print.key=true --timeout-ms 5000 ;;
  *)
    echo "unknown action: $WHAT" >&2
    exit 1 ;;
esac
