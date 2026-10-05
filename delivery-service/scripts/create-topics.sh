#!/usr/bin/env bash
# Creates the topics this service uses (3 partitions each). Safe to re-run.
# The orders.* topics belong to the Order Service; --if-not-exists keeps us from clashing with them.
set -euo pipefail

KAFKA_CONTAINER="${KAFKA_CONTAINER:-kafka}"
BOOTSTRAP="${BOOTSTRAP:-kafka:19092}"

for topic in orders.created orders.status.changed \
             deliveries.driver.assigned deliveries.status.changed deliveries.location.updated; do
  docker compose -f docker-compose.dev.yml exec -T "$KAFKA_CONTAINER" \
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP" \
    --create --if-not-exists --topic "$topic" --partitions 3 --replication-factor 1
done
