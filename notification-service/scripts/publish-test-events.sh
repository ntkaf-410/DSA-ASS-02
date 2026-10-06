#!/usr/bin/env bash
# Plays all the other services: one customer signs up and one order goes from placed to delivered.
# Afterwards the customer's inbox should hold the whole story:
#   curl -s localhost:8086/notifications/customers/<customer-id>
#
#   ./scripts/publish-test-events.sh              # customer 1, order order-1
#   ./scripts/publish-test-events.sh 7 order-42   # customer 7, order order-42
set -euo pipefail

CUSTOMER_ID="${1:-1}"
ORDER_ID="${2:-order-1}"
KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"
BOOTSTRAP="${BOOTSTRAP:-kafka:19092}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

send() { # topic key payload
  printf '%s:%s\n' "$2" "$3" | docker compose -f docker-compose.dev.yml exec -T "$KAFKA_CONTAINER" \
    /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server "$BOOTSTRAP" \
    --topic "$1" --property parse.key=true --property key.separator=:
  echo "sent $1"
}

status() { send orders.status.changed "$ORDER_ID" "{\"orderId\":\"$ORDER_ID\",\"status\":\"$1\"}"; }

send customers.registered "$CUSTOMER_ID" \
  "{\"eventType\":\"CUSTOMER_REGISTERED\",\"customerId\":$CUSTOMER_ID,\"fullName\":\"Ndapanda Shikongo\",\"email\":\"nd@example.com\",\"phone\":\"+264811234567\",\"occurredAt\":\"$NOW\"}"

send orders.created "$ORDER_ID" \
  "{\"orderId\":\"$ORDER_ID\",\"customerId\":$CUSTOMER_ID,\"restaurantId\":1,\"totalAmount\":185.50,\"deliveryAddressId\":1,\"items\":[]}"
# give the consumer a second, otherwise the status events can overtake orders.created
sleep 2

send payments.completed "$ORDER_ID" "{\"orderId\":\"$ORDER_ID\"}"
status CONFIRMED
status PREPARING
status READY

send deliveries.driver.assigned "$ORDER_ID" \
  "{\"eventType\":\"DRIVER_ASSIGNED\",\"orderId\":\"$ORDER_ID\",\"customerId\":$CUSTOMER_ID,\"restaurantId\":1,\"driverId\":1,\"driverName\":\"Johannes Shilongo\",\"driverPhone\":\"+264811000001\",\"vehicle\":\"motorbike\",\"plateNumber\":\"N 1001 W\",\"occurredAt\":\"$NOW\"}"

send deliveries.status.changed "$ORDER_ID" \
  "{\"eventType\":\"DELIVERY_OUT_FOR_DELIVERY\",\"orderId\":\"$ORDER_ID\",\"status\":\"OUT_FOR_DELIVERY\",\"customerId\":$CUSTOMER_ID,\"driverId\":1,\"occurredAt\":\"$NOW\"}"
# the Order Service repeats this one, it must NOT produce a second "On its way"
status OUT_FOR_DELIVERY

send deliveries.status.changed "$ORDER_ID" \
  "{\"eventType\":\"DELIVERY_DELIVERED\",\"orderId\":\"$ORDER_ID\",\"status\":\"DELIVERED\",\"customerId\":$CUSTOMER_ID,\"driverId\":1,\"occurredAt\":\"$NOW\"}"
status DELIVERED

send restaurants.stock.low 1 \
  "{\"eventType\":\"STOCK_LOW\",\"restaurantId\":1,\"menuItemId\":3,\"itemName\":\"Kapana roll\",\"stockQuantity\":2,\"occurredAt\":\"$NOW\"}"
