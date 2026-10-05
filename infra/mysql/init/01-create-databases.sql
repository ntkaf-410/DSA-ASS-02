-- Runs once, the first time the platform MySQL container starts with an empty data volume.
-- One schema per service: they share a MySQL server to keep the stack light enough for a
-- laptop, but no service ever reads another service's schema (they talk over REST and Kafka).
-- The tables themselves are created by each service on startup.

CREATE DATABASE IF NOT EXISTS customer_db     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS restaurant_db   CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS order_db        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS payment_db      CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS delivery_db     CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS notification_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS admin_db        CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
