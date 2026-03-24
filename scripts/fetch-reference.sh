#!/usr/bin/env bash
set -euo pipefail

# Fair Fuel Open Data API — weekly reference data fetcher
# Fetches station, brand, and fuel type reference data.

BASE_URL="https://api.fuel.service.vic.gov.au/open-data/v1"
DATE=$(date -u +%Y-%m-%d)

# --- Pre-flight checks ---
if [[ -z "${FAIR_FUEL_CONSUMER_ID:-}" ]]; then
  echo "ERROR: FAIR_FUEL_CONSUMER_ID is not set" >&2
  exit 1
fi

# --- Generic fetch function with retry ---
fetch_endpoint() {
  local endpoint="$1"
  local txn_id
  txn_id=$(python3 -c "import uuid; print(uuid.uuid4())")

  curl -sf -w "\n%{http_code}" \
    -H "User-Agent: FairFuelArchiver/1.0" \
    -H "x-consumer-id: ${FAIR_FUEL_CONSUMER_ID}" \
    -H "x-transactionid: ${txn_id}" \
    "${BASE_URL}${endpoint}"
}

fetch_with_retry() {
  local endpoint="$1"
  local label="$2"

  echo "Fetching ${label}..." >&2

  local response http_code body

  response=$(fetch_endpoint "$endpoint") || {
    echo "First attempt for ${label} failed — retrying in 10 seconds..." >&2
    sleep 10
    response=$(fetch_endpoint "$endpoint") || {
      echo "Second attempt for ${label} also failed." >&2
      exit 1
    }
  }

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" != "200" ]]; then
    echo "API returned HTTP ${http_code} for ${label}" >&2
    echo "Response body: ${body}" >&2
    echo "Retrying in 10 seconds..." >&2
    sleep 10

    response=$(fetch_endpoint "$endpoint") || {
      echo "Retry for ${label} failed." >&2
      exit 1
    }
    http_code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
      echo "Retry for ${label} also returned HTTP ${http_code}" >&2
      echo "Response body: ${body}" >&2
      exit 1
    fi
  fi

  echo "$body"
}

# --- Helper: save only if data has changed from the latest snapshot ---
save_if_changed() {
  local label="$1"
  local raw_file="$2"
  local raw_dir="$3"
  local ref_file="$4"
  local data="$5"

  # Find the most recent existing snapshot
  local latest
  latest=$(ls -1 "${raw_dir}"/*.json 2>/dev/null | sort | tail -1)

  if [[ -n "$latest" ]] && printf '%s' "$data" | diff -q - "$latest" > /dev/null 2>&1; then
    echo "${label} data unchanged from $(basename "$latest") — skipping."
    return
  fi

  printf '%s' "$data" > "$raw_file"
  echo "Saved $raw_file"
  cp "$raw_file" "$ref_file"
  echo "Updated $ref_file"
}

# --- Fetch and save each reference dataset ---

# Stations
STATIONS_RAW="data/raw/stations/stations-${DATE}.json"
if [[ -f "$STATIONS_RAW" ]]; then
  echo "Stations file already exists for ${DATE} — skipping."
else
  STATIONS=$(fetch_with_retry "/fuel/reference-data/stations" "stations")
  # Strip contactPhone fields to avoid storing personal information (ToS clause 7)
  STATIONS=$(echo "$STATIONS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for s in data.get('fuelStations', []):
    s.pop('contactPhone', None)
json.dump(data, sys.stdout, separators=(',', ':'))
")
  save_if_changed "Stations" "$STATIONS_RAW" "data/raw/stations" "data/reference/stations.json" "$STATIONS"
fi

# Brands
BRANDS_RAW="data/raw/brands/brands-${DATE}.json"
if [[ -f "$BRANDS_RAW" ]]; then
  echo "Brands file already exists for ${DATE} — skipping."
else
  BRANDS=$(fetch_with_retry "/fuel/reference-data/brands" "brands")
  save_if_changed "Brands" "$BRANDS_RAW" "data/raw/brands" "data/reference/brands.json" "$BRANDS"
fi

# Fuel types
TYPES_RAW="data/raw/types/types-${DATE}.json"
if [[ -f "$TYPES_RAW" ]]; then
  echo "Types file already exists for ${DATE} — skipping."
else
  TYPES=$(fetch_with_retry "/fuel/reference-data/types" "fuel types")
  save_if_changed "Types" "$TYPES_RAW" "data/raw/types" "data/reference/types.json" "$TYPES"
fi

echo "Done — all reference data fetched for ${DATE}."
