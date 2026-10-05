#!/usr/bin/env bash
set -euo pipefail

ready=false
for attempt in {1..30}; do
  if docker compose -f docker-compose.dev.yml exec -T kafka \
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:19092 --list >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 2
done
if [[ "$ready" != true ]]; then
  echo "Kafka did not become ready within 60 seconds" >&2
  exit 1
fi

for topic in orders.created payments.completed payments.failed; do
  docker compose -f docker-compose.dev.yml exec -T kafka \
    /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:19092 \
    --create --if-not-exists --topic "$topic" --partitions 3 --replication-factor 1
done
