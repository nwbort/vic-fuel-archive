#!/usr/bin/env python3
"""Flatten raw price JSON into a Parquet file, appending to existing data."""

import json
import os
import sys

import pyarrow as pa
import pyarrow.parquet as pq

SCHEMA = pa.schema([
    ("date", pa.string()),
    ("station_id", pa.string()),
    ("brand_id", pa.string()),
    ("fuel_type", pa.string()),
    ("price", pa.float32()),
    ("is_available", pa.bool_()),
    ("price_updated_at", pa.string()),
])


def json_to_table(data, date):
    """Convert raw API JSON to a PyArrow table."""
    dates, station_ids, brand_ids, fuel_types = [], [], [], []
    prices, availabilities, updated_ats = [], [], []

    for detail in data["fuelPriceDetails"]:
        station = detail["fuelStation"]
        for fp in detail["fuelPrices"]:
            dates.append(date)
            station_ids.append(station["id"])
            brand_ids.append(station["brandId"])
            fuel_types.append(fp["fuelType"])
            p = fp.get("price")
            prices.append(float(p) if p is not None else None)
            availabilities.append(fp.get("isAvailable", False))
            updated_ats.append(fp.get("updatedAt", ""))

    return pa.table(
        {
            "date": pa.array(dates, type=pa.string()),
            "station_id": pa.array(station_ids, type=pa.string()),
            "brand_id": pa.array(brand_ids, type=pa.string()),
            "fuel_type": pa.array(fuel_types, type=pa.string()),
            "price": pa.array(prices, type=pa.float32()),
            "is_available": pa.array(availabilities, type=pa.bool_()),
            "price_updated_at": pa.array(updated_ats, type=pa.string()),
        },
        schema=SCHEMA,
    )


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <date> <parquet-file>", file=sys.stderr)
        sys.exit(1)

    date = sys.argv[1]
    parquet_file = sys.argv[2]

    data = json.load(sys.stdin)
    new_table = json_to_table(data, date)

    if os.path.exists(parquet_file):
        existing = pq.read_table(parquet_file, schema=SCHEMA)
        new_table = pa.concat_tables([existing, new_table])

    pq.write_table(new_table, parquet_file, compression="zstd")
    print(f"Written {len(new_table)} total rows to {parquet_file}")


if __name__ == "__main__":
    main()
