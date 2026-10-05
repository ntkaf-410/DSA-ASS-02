# Admin Service

**Language:** Ballerina (Swan Lake) · **DB:** MySQL 8 (`admin_db`) · **Messaging:** Kafka (consume only) · **Port:** `8087`

Reports for the platform owner, plus a status page for the other services.

## How it works

The service never queries another service's database. It listens to every business topic with its
own consumer group and keeps a small read model in `admin_db` (`rpt_orders`, `rpt_customers`,
`rpt_deliveries`, `rpt_low_stock`). Reports are plain SQL on those tables.

- Rows are dated with the Kafka record timestamp, so replaying a topic rebuilds the history on the right days.
- Every write is an upsert: duplicates are harmless, and events that overtake each other across topics
  (a payment arriving before its `orders.created`) end up in the same row.
- `admin_db` can be dropped at any time. Start the service with a new `consumerGroupId` and it rebuilds itself.

## Topics consumed

`customers.registered`, `orders.created`, `orders.status.changed`, `restaurants.order.status`,
`restaurants.stock.low`, `payments.completed`, `payments.failed`, `deliveries.driver.assigned`,
`deliveries.status.changed`

## REST API

| Method | Path | Notes |
|---|---|---|
| GET | `/admin/reports/summary` | Totals for the dashboard: orders, revenue, average order value, average delivery time, customers |
| GET | `/admin/reports/orders/status` | Orders and amount per status |
| GET | `/admin/reports/revenue/daily?days=30` | Orders, cancellations and revenue per day (1-365 days) |
| GET | `/admin/reports/restaurants?limit=10` | Restaurants by revenue |
| GET | `/admin/reports/customers?limit=10` | Customers by amount spent |
| GET | `/admin/reports/drivers` | Jobs per driver, average minutes from assignment to drop-off |
| GET | `/admin/reports/deliveries` | Deliveries per status |
| GET | `/admin/reports/stock?limit=20` | Latest low-stock warnings |
| GET | `/admin/orders?status=&restaurantId=&customerId=&page=&pageSize=` | All orders, newest first |
| GET | `/admin/services` | Pings `/health` of the six other services (always 200, status per service in the body) |
| GET | `/health` | DB ping, used by the Docker healthcheck |

Revenue always means paid orders that were not cancelled. Errors use the shared body `{"code":"...","message":"..."}`.

## Run it

```bash
# on its own
docker compose -f docker-compose.dev.yml up -d mysql kafka
cp Config.toml.example Config.toml
bal run                                  # http://localhost:8087
./scripts/publish-test-events.sh         # fake one full order
curl -s localhost:8087/admin/reports/summary

# with the whole platform (from the repo root)
docker compose up -d --build
```

## Known limitations

No authentication on `/admin` yet. Refunds are not modelled, a cancelled order simply stops counting as revenue.
There is no notification report because the Notification Service does not publish events.
