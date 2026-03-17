#!/usr/bin/env bash
set -euo pipefail

# Fair Fuel Open Data API — daily price fetcher
# Fetches all Victorian fuel station prices and archives the raw JSON,
# then flattens into an append-only CSV.

BASE_URL="https://api.fuel.service.vic.gov.au/open-data/v1"
DATE=$(date -u +%Y-%m-%d)
RAW_DIR="data/raw/prices"
CSV_FILE="data/processed/prices.csv"
RAW_FILE="${RAW_DIR}/prices-${DATE}.json.gz"

# --- Pre-flight checks ---
if [[ -z "${FAIR_FUEL_CONSUMER_ID:-}" ]]; then
  echo "ERROR: FAIR_FUEL_CONSUMER_ID is not set" >&2
  exit 1
fi

# --- Idempotency: skip if today's file already exists ---
if [[ -f "$RAW_FILE" ]]; then
  echo "Raw file $RAW_FILE already exists — skipping fetch and flatten."
  exit 0
fi

# --- Fetch prices ---
fetch_prices() {
  local txn_id
  txn_id=$(python3 -c "import uuid; print(uuid.uuid4())")

  curl -sf -w "\n%{http_code}" \
    -H "User-Agent: FairFuelArchiver/1.0" \
    -H "x-consumer-id: ${FAIR_FUEL_CONSUMER_ID}" \
    -H "x-transactionid: ${txn_id}" \
    "${BASE_URL}/fuel/prices"
}

echo "Fetching prices for ${DATE}..."

RESPONSE=$(fetch_prices) || {
  echo "First attempt failed — retrying in 10 seconds..." >&2
  sleep 10
  RESPONSE=$(fetch_prices) || {
    echo "Second attempt also failed." >&2
    # Extract status code from last line
    HTTP_CODE=$(echo "$RESPONSE" | tail -1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    echo "HTTP status: ${HTTP_CODE}" >&2
    echo "Response body: ${BODY}" >&2
    exit 1
  }
}

# Separate body from status code
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "API returned HTTP ${HTTP_CODE}" >&2
  echo "Response body: ${BODY}" >&2
  echo "Retrying in 10 seconds..." >&2
  sleep 10

  RESPONSE=$(fetch_prices) || {
    echo "Retry failed." >&2
    exit 1
  }
  HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  BODY=$(echo "$RESPONSE" | sed '$d')

  if [[ "$HTTP_CODE" != "200" ]]; then
    echo "Retry also returned HTTP ${HTTP_CODE}" >&2
    echo "Response body: ${BODY}" >&2
    exit 1
  fi
fi

echo "Got HTTP 200 — archiving raw response..."

# --- Save raw gzipped JSON ---
echo "$BODY" | gzip > "$RAW_FILE"
echo "Saved $RAW_FILE"

# --- Flatten to CSV ---
echo "Flattening to ${CSV_FILE}..."

# Write header if file doesn't exist
if [[ ! -f "$CSV_FILE" ]]; then
  echo "date,station_id,brand_id,fuel_type,price,is_available,price_updated_at" > "$CSV_FILE"
fi

# Use jq to flatten the nested JSON structure
echo "$BODY" | jq -r --arg date "$DATE" '
  .fuelPriceDetails[] |
  .fuelStation as $station |
  .fuelPrices[] |
  [
    $date,
    $station.id,
    $station.brandId,
    .fuelType,
    (if .price == null or (.price | type) == "object" then "" else (.price | tostring) end),
    (if .isAvailable then "true" else "false" end),
    (.updatedAt // "")
  ] | @csv
' >> "$CSV_FILE"

echo "Done — appended prices for ${DATE} to ${CSV_FILE}"
