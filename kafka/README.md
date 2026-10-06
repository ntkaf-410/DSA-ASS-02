# Kafka topics

`create-topics.sh` is the master list. `docker compose up` runs it once through the `kafka-init`
container; to run it by hand against the running stack: `./kafka/create-topics.sh` from the repo root.

All topics have 3 partitions. Producers key by the id in the "Key" column, so events about the same
order (or customer) stay in one partition and are consumed in the order they were produced.

| Topic | Key | Produced by | Consumed by |
|---|---|---|---|
| `customers.registered` | customerId | customer | notification, admin |
| `orders.created` | orderId | order | customer, restaurant, payment, delivery, notification, admin |
| `orders.status.changed` | orderId | order | customer, restaurant, delivery, notification, admin |
| `restaurants.order.status` | orderId | restaurant | order, admin |
| `restaurants.stock.low` | restaurantId | restaurant | notification, admin |
| `payments.completed` | orderId | payment | order, notification, admin |
| `payments.failed` | orderId | payment | order, notification, admin |
| `deliveries.driver.assigned` | orderId | delivery | notification, admin |
| `deliveries.status.changed` | orderId | delivery | order, notification, admin |
| `deliveries.location.updated` | orderId | delivery | live map (1 hour retention) |

Each service has its own consumer group (`<service>-group`), so every service gets its own copy of
an event and two instances of the same service split the partitions between them.

Adding a topic: add it to `TOPICS` in `create-topics.sh` and to this table.
