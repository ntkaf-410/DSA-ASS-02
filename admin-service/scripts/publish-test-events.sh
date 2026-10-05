#!/usr/bin/env bash
# Fakes one complete order (registration -> order -> payment -> kitchen -> driver -> delivered)
# so the reports have something to show when the other services aren't running.
#
#   ./scripts/publish-test-events.sh                 # random order id, customer 1, restaurant 1, N$ 185.50
#   ./scripts/publish-test-events.sh ord-42 2 3 99   # order id, customer id, restaurant id, amount
#
# Uses the kafka container of docker-compose.dev.yml. Against the full platform stack run it
# from the repo root with COMPOSE_FILE=docker-compose.yml.
set -euo pipefail

ORDER_ID="${1:-demo-$(date +%s)}"
CUSTOMER_ID="${2:-1}"
RESTAURANT_ID="${3:-1}"
AMOUNT="${4:-185.50}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.dev.yml}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

send() { # topic key payload
  printf '%s|%s\n' "$2" "$3" | docker compose -f "$COMPOSE_FILE" exec -T kafka \
    /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:19092 \
    --topic "$1" --property parse.key=true --property key.separator='|'
}

send customers.registered "$CUSTOMER_ID" \
  "{\"eventType\":\"CUSTOMER_REGISTERED\",\"customerId\":$CUSTOMER_ID,\"fullName\":\"Demo Customer $CUSTOMER_ID\",\"email\":\"demo$CUSTOMER_ID@example.com\",\"phone\":\"+264811234567\",\"occurredAt\":\"$NOW\"}"

send orders.created "$ORDER_ID" \
  "{\"orderId\":\"$ORDER_ID\",\"customerId\":$CUSTOMER_ID,\"restaurantId\":$RESTAURANT_ID,\"totalAmount\":$AMOUNT,\"deliveryAddressId\":1,\"items\":[]}"

send payments.completed "$ORDER_ID" "{\"orderId\":\"$ORDER_ID\"}"

for status in CONFIRMED PREPARING READY; do
  send orders.status.changed "$ORDER_ID" "{\"orderId\":\"$ORDER_ID\",\"status\":\"$status\"}"
done

send deliveries.driver.assigned "$ORDER_ID" \
  "{\"eventType\":\"DRIVER_ASSIGNED\",\"orderId\":\"$ORDER_ID\",\"customerId\":$CUSTOMER_ID,\"restaurantId\":$RESTAURANT_ID,\"driverId\":1,\"driverName\":\"Demo Driver\",\"driverPhone\":\"+264811000001\",\"vehicle\":\"motorbike\",\"plateNumber\":null,\"occurredAt\":\"$NOW\"}"

for status in OUT_FOR_DELIVERY DELIVERED; do
  send deliveries.status.changed "$ORDER_ID" \
    "{\"eventType\":\"DELIVERY_$status\",\"orderId\":\"$ORDER_ID\",\"status\":\"$status\",\"customerId\":$CUSTOMER_ID,\"driverId\":1,\"occurredAt\":\"$NOW\"}"
  send orders.status.changed "$ORDER_ID" "{\"orderId\":\"$ORDER_ID\",\"status\":\"$status\"}"
done

echo "Published a full order flow for $ORDER_ID. Try: curl -s localhost:8087/admin/reports/summary"
