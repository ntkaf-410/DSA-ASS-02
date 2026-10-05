#!/usr/bin/env bash
# Pretends to be the Order Service so you can test without Person 3's code.
# Usage: ./scripts/publish-test-events.sh <orderId> [restaurantId] [menuItemId] [quantity]
# Run seed-demo.sh first. Watch the result with:
#   docker compose -f docker-compose.dev.yml exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
#     --bootstrap-server kafka:19092 --topic restaurants.order.status --from-beginning
set -euo pipefail

ORDER_ID="${1:?usage: $0 <orderId> [restaurantId] [menuItemId] [quantity]}"
RESTAURANT="${2:-1}"
ITEM="${3:-1}"
QTY="${4:-1}"

send() { # topic, key, json
  echo "$2:$3" | docker compose -f docker-compose.dev.yml exec -T kafka \
    /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:19092 \
    --topic "$1" --property parse.key=true --property key.separator=:
}

echo "-> orders.created for $ORDER_ID"
send orders.created "$ORDER_ID" \
  "{\"orderId\":\"$ORDER_ID\",\"customerId\":1,\"restaurantId\":$RESTAURANT,\"totalAmount\":145.00,\"items\":[{\"menuItemId\":$ITEM,\"quantity\":$QTY}]}"

echo "To test a cancel (stock should go back up):"
echo "  echo '$ORDER_ID:{\"orderId\":\"$ORDER_ID\",\"status\":\"CANCELLED\"}' | docker compose -f docker-compose.dev.yml exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:19092 --topic orders.status.changed --property parse.key=true --property key.separator=:"
