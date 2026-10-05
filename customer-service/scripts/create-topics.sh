#!/usr/bin/env bash
# Creates the topics this service touches (Person 6 owns the master version).
# Partitions = 3 so up to 3 consumer instances can share the load;
# messages are keyed (customerId / orderId) so per-key ordering is preserved.
set -euo pipefail
KAFKA_CONTAINER="${KAFKA_CONTAINER:-$(docker compose -f docker-compose.dev.yml ps -q kafka)}"
for topic in customers.registered orders.created orders.status.changed; do
  docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server localhost:9092 --create --if-not-exists \
    --topic "$topic" --partitions 3 --replication-factor 1
done
docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
