#!/usr/bin/env bash
# Simulates the Order Service so you can test order history without Person 3's code.
# Usage: ./scripts/publish-test-events.sh <customerId> [orderId]
set -euo pipefail
CID="${1:?customerId required}"; OID="${2:-ORD-$(date +%s)}"
K="$(docker compose -f docker-compose.dev.yml ps -q kafka)"
send() { # topic, key, json
  echo "$2:$3" | docker exec -i "$K" /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$1" --property parse.key=true --property key.separator=:
}
send orders.created "$OID" "{\"orderId\":\"$OID\",\"customerId\":$CID,\"restaurantId\":\"REST-1\",\"totalAmount\":149.50,\"deliveryAddressId\":1,\"items\":[{\"name\":\"Kapana combo\",\"qty\":2,\"price\":59.75}]}"
sleep 1
for s in CONFIRMED PREPARING READY OUT_FOR_DELIVERY DELIVERED; do
  send orders.status.changed "$OID" "{\"orderId\":\"$OID\",\"status\":\"$s\"}"; sleep 1
done
echo "Published lifecycle for $OID -> GET /customers/$CID/orders"
