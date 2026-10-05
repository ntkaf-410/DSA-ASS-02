#!/usr/bin/env bash
# Fakes Restaurant (P2) / Payment (P4) / Delivery (P5) events so the Order Service can be tested alone.
# usage: ./simulate-events.sh <orderId> <action>
#   restaurant-confirm | restaurant-reject | preparing | ready |
#   payment-ok | payment-fail | out-for-delivery | delivered
set -e
KAFKA_CONTAINER=${KAFKA_CONTAINER:-order-kafka}
ORDER_ID=$1; WHAT=$2
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
send() { # topic payload
  echo "$ORDER_ID:$2" | docker exec -i "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server localhost:9092 --topic "$1" --property parse.key=true --property key.separator=:
}
rest() { send restaurants.order.status "{\"eventType\":\"ORDER_STATUS\",\"orderId\":\"$ORDER_ID\",\"restaurantId\":1,\"status\":\"$1\",\"reason\":$2,\"occurredAt\":\"$NOW\"}"; }
case "$WHAT" in
  restaurant-confirm) rest CONFIRMED null ;;
  restaurant-reject)  rest REJECTED '"out of stock"' ;;
  preparing)          rest PREPARING null ;;
  ready)              rest READY null ;;
  payment-ok)         send payments.completed "{\"orderId\":\"$ORDER_ID\",\"paymentId\":\"p1\",\"status\":\"PAID\"}" ;;
  payment-fail)       send payments.failed "{\"orderId\":\"$ORDER_ID\",\"reason\":\"insufficient funds\"}" ;;
  out-for-delivery)   send deliveries.status.changed "{\"orderId\":\"$ORDER_ID\",\"status\":\"OUT_FOR_DELIVERY\"}" ;;
  delivered)          send deliveries.status.changed "{\"orderId\":\"$ORDER_ID\",\"status\":\"DELIVERED\"}" ;;
  *) echo "unknown action"; exit 1 ;;
esac
