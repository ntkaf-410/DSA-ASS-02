#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <order-id> <amount>" >&2
  exit 2
fi

order_id="$1"
amount="$2"
payload="{\"orderId\":\"${order_id}\",\"customerId\":1,\"restaurantId\":1,\"totalAmount\":${amount},\"deliveryAddressId\":1,\"items\":[]}"
printf '%s:%s\n' "$order_id" "$payload" | docker compose -f docker-compose.dev.yml exec -T kafka \
  /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:19092 \
  --topic orders.created --property parse.key=true --property key.separator=:
