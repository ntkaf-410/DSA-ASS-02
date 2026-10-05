#!/usr/bin/env bash
# Master list of every Kafka topic on the platform. The per-service scripts only create
# what that one service touches, this one is what the full docker-compose.yml runs.
#
# Two ways to run it:
#   1) automatically - the `kafka-init` container in docker-compose.yml runs it once on `up`
#   2) by hand from the repo root, against the running broker:
#        ./kafka/create-topics.sh
#
# Safe to run as often as you like (--if-not-exists).
set -euo pipefail

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-kafka:19092}"
PARTITIONS="${PARTITIONS:-3}"
REPLICATION_FACTOR="${REPLICATION_FACTOR:-1}"   # single broker, so 1 is all we can have
KAFKA_BIN="${KAFKA_BIN:-/opt/kafka/bin}"

# Not inside a Kafka image? Then hand the script to the broker container and let it run there,
# so nobody needs the Kafka CLI installed on their laptop.
if [[ ! -x "$KAFKA_BIN/kafka-topics.sh" ]]; then
  echo "Kafka CLI not found locally, running inside the kafka container..."
  exec docker compose exec -T \
    -e BOOTSTRAP_SERVER="$BOOTSTRAP_SERVER" -e PARTITIONS="$PARTITIONS" -e REPLICATION_FACTOR="$REPLICATION_FACTOR" \
    kafka bash -s < "$0"
fi

# 3 partitions each: up to 3 instances of a consumer group can share the load.
# All producers key by orderId / customerId / restaurantId, so events about the same
# order still land in one partition and stay in order.
TOPICS=(
  customers.registered        # customer-service   -> notification, admin
  orders.created              # order-service      -> customer, restaurant, payment, delivery, notification, admin
  orders.status.changed       # order-service      -> customer, restaurant, delivery, notification, admin
  restaurants.order.status    # restaurant-service -> order, admin
  restaurants.stock.low       # restaurant-service -> notification, admin
  payments.completed          # payment-service    -> order, notification, admin
  payments.failed             # payment-service    -> order, notification, admin
  deliveries.driver.assigned  # delivery-service   -> notification, admin
  deliveries.status.changed   # delivery-service   -> order, notification, admin
)

# GPS pings are only interesting while the food is on the road. Kept for an hour
# instead of the default 7 days so the topic doesn't grow forever.
LOCATION_TOPIC="deliveries.location.updated"   # delivery-service -> (live map)
LOCATION_RETENTION_MS="${LOCATION_RETENTION_MS:-3600000}"

# The broker container reports "started" a few seconds before it really accepts requests.
echo "Waiting for Kafka at $BOOTSTRAP_SERVER ..."
ready=false
for attempt in $(seq 1 30); do
  if "$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP_SERVER" --list >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  echo "Kafka did not become ready within 60 seconds" >&2
  exit 1
fi

for topic in "${TOPICS[@]}"; do
  "$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP_SERVER" \
    --create --if-not-exists --topic "$topic" \
    --partitions "$PARTITIONS" --replication-factor "$REPLICATION_FACTOR"
done

"$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP_SERVER" \
  --create --if-not-exists --topic "$LOCATION_TOPIC" \
  --partitions "$PARTITIONS" --replication-factor "$REPLICATION_FACTOR" \
  --config "retention.ms=$LOCATION_RETENTION_MS"

echo
echo "Topics on $BOOTSTRAP_SERVER:"
"$KAFKA_BIN/kafka-topics.sh" --bootstrap-server "$BOOTSTRAP_SERVER" --list
