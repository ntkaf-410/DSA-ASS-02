set -e
KAFKA_CONTAINER=${KAFKA_CONTAINER:-order-kafka}
for t in orders.created orders.status.changed payments.completed payments.failed \
         deliveries.status.changed restaurants.order.status; do
  docker exec "$KAFKA_CONTAINER" /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 \
    --create --if-not-exists --topic "$t" --partitions 3 --replication-factor 1
done
