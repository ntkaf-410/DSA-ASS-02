#!/usr/bin/env bash
# Puts one restaurant, a week of opening hours and a small menu in through the REST API.
# Usage: ./scripts/seed-demo.sh [base-url]
set -euo pipefail
BASE="${1:-http://localhost:8082}"
JSON='Content-Type: application/json'

curl -s -X POST "$BASE/restaurants" -H "$JSON" -d '{
  "name": "Kalahari Grill", "cuisine": "Braai", "phone": "+264611234567",
  "description": "Grilled meat and sides", "address": "12 Independence Ave",
  "city": "Windhoek", "latitude": -22.5609, "longitude": 17.0658 }'
echo

# open every day 06:00 - 23:00 so the demo works whenever you run it
curl -s -X PUT "$BASE/restaurants/1/hours" -H "$JSON" -d '[
  {"dayOfWeek":0,"openTime":"06:00","closeTime":"23:00"},
  {"dayOfWeek":1,"openTime":"06:00","closeTime":"23:00"},
  {"dayOfWeek":2,"openTime":"06:00","closeTime":"23:00"},
  {"dayOfWeek":3,"openTime":"06:00","closeTime":"23:00"},
  {"dayOfWeek":4,"openTime":"06:00","closeTime":"23:00"},
  {"dayOfWeek":5,"openTime":"06:00","closeTime":"23:00"},
  {"dayOfWeek":6,"openTime":"06:00","closeTime":"23:00"}]'
echo

curl -s -X POST "$BASE/restaurants/1/menu" -H "$JSON" \
  -d '{"name":"Ribeye Steak","category":"Mains","price":145.00,"stockQuantity":10}'
echo
curl -s -X POST "$BASE/restaurants/1/menu" -H "$JSON" \
  -d '{"name":"Boerewors Roll","category":"Mains","price":55.00,"stockQuantity":3}'
echo
curl -s -X POST "$BASE/restaurants/1/menu" -H "$JSON" \
  -d '{"name":"Ginger Beer","category":"Drinks","price":18.50,"stockQuantity":50}'
echo
