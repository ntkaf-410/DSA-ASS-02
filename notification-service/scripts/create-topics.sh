#!/usr/bin/env bash
# Creates every topic this service listens to (3 partitions each). Safe to re-run.
# None of them are ours, --if-not-exists keeps us from clashing with the services that own them.
set -euo pipefail

KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"
BOOTSTRAP="${BOOTSTRAP:-kafka:19092}"

for topic in customers.registered orders.created orders.status.changed \
             payments.completed payments.failed restaurants.stock.low \
             deliveries.driver.assigned deliveries.status.changed; do
  docker compose -f docker-compose.dev.yml exec -T "$KAFKA_CONTAINER" \
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists --topic "$topic" --partitions 3 --replication-factor 1
done
