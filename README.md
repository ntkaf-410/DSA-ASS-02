## Basic instructions to run the system

### 1. Install prerequisites

You need:

- Docker Desktop
- Ballerina Swan Lake, if running services locally
- Git, if cloning the project

### 2. Open PowerShell in the project folder

```powershell
cd "C:\Users\Tenebi 1\Documents\DSA 2"
```

### 3. Start the complete system

```powershell
docker compose up -d --build
```

This starts MySQL, Kafka, and all services.

### 4. Check that containers are running

```powershell
docker compose ps
```

All services should show as running or healthy.

### 5. Test service health

Open these URLs in a browser or use them in PowerShell:

```text
http://localhost:8081/health   Customer Service
http://localhost:8082/health   Restaurant Service
http://localhost:8083/health   Order Service
http://localhost:8084/health   Payment Service
http://localhost:8085/health   Delivery Service
http://localhost:8086/health   Notification Service
http://localhost:8087/health   Admin Service
```

### 6. View logs if something fails

```powershell
docker compose logs -f
```

To view only one service:

```powershell
docker compose logs -f customer-service
```

### 7. Stop the system

```powershell
docker compose down
```

To also delete the stored database data:

```powershell
docker compose down -v
```

## Basic customer test

Register a customer:

```powershell
curl.exe -X POST http://localhost:8081/customers `
  -H "Content-Type: application/json" `
  -d '{\"fullName\":\"Test User\",\"email\":\"test@example.com\",\"phone\":\"0812345678\",\"password\":\"Secret123\"}'
```

Log in:

```powershell
curl.exe -X POST http://localhost:8081/customers/login `
  -H "Content-Type: application/json" `
  -d '{\"email\":\"test@example.com\",\"password\":\"Secret123\"}'
```

List customers:

```powershell
curl.exe http://localhost:8081/customers
```

## If running the Customer Service manually

From the customer-service folder:

```powershell
cd "C:\Users\Tenebi 1\Documents\DSA 2\customer-service"
Copy-Item Config.toml.example Config.toml
bal run
```

The Customer Service will then be available at:

```text
http://localhost:8081
```

For the presentation, the simplest command to remember is:

```powershell
docker compose up -d --build
```

Then demonstrate the `/health` endpoints and a customer registration request.

**Task completed:**

Provided short, basic instructions for starting the Docker Compose system, checking service health, viewing logs, stopping containers, testing customer endpoints, and optionally running the Customer Service locally.