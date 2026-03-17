# Victorian Fair Fuel Price Archive

Automated daily archive of Victorian fuel prices from the [Fair Fuel Open Data API](https://www.service.vic.gov.au/), maintained via GitHub Actions.

## What this does

- **Daily** (2 pm UTC / midnight AEST): fetches all fuel station prices across Victoria, saves the raw JSON (gzipped), and appends a flat row per station/fuel-type to `data/processed/prices.csv`.
- **Weekly** (3 pm UTC Sunday): fetches reference data — stations, brands, and fuel types — and saves both dated snapshots and convenience "latest" copies.

All data is committed back to the repository automatically.

## Data source

Data comes from the **Victorian Fair Fuel Open Data API**, published by Service Victoria.

- Base URL: `https://api.fuel.service.vic.gov.au/open-data/v1`
- Prices are **~24 hours delayed** from real-time retailer submissions.
- Access requires a registered Consumer ID — see [Service Victoria](https://www.service.vic.gov.au/) for registration.

## Repository structure

```
├── .github/workflows/
│   ├── daily-prices.yml         # Runs daily at 2 pm UTC
│   └── weekly-reference.yml     # Runs weekly on Sunday at 3 pm UTC
├── scripts/
│   ├── fetch-prices.sh          # Fetches + archives prices
│   └── fetch-reference.sh       # Fetches + archives reference data
├── data/
│   ├── raw/
│   │   ├── prices/              # prices-YYYY-MM-DD.json.gz
│   │   ├── stations/            # stations-YYYY-MM-DD.json
│   │   ├── brands/              # brands-YYYY-MM-DD.json
│   │   └── types/               # types-YYYY-MM-DD.json
│   ├── processed/
│   │   └── prices.csv           # Append-only flat CSV
│   └── reference/
│       ├── stations.json        # Latest station metadata
│       ├── brands.json          # Latest brand lookup
│       └── types.json           # Latest fuel type codes
└── README.md
```

## CSV schema (`data/processed/prices.csv`)

| Column | Description |
|---|---|
| `date` | Fetch date (YYYY-MM-DD) |
| `station_id` | Fuel station identifier (join with `stations.json`) |
| `brand_id` | Brand identifier (join with `brands.json`) |
| `fuel_type` | Fuel type code, e.g. U91, P95, DSL (join with `types.json`) |
| `price` | Price in AUD cents per litre (empty string if unavailable) |
| `is_available` | `true` or `false` |
| `price_updated_at` | ISO 8601 timestamp of last price update |

Prices are in **cents per litre** with one decimal place (e.g. `165.0` = $1.65/L). When a fuel type is unavailable at a station, `price` will be empty and `is_available` will be `false`.

## Setup

1. **Fork or clone** this repository.
2. Go to **Settings > Secrets and variables > Actions** and add a repository secret:
   - Name: `FAIR_FUEL_CONSUMER_ID`
   - Value: your API Consumer ID issued by Service Victoria
3. The workflows will run on schedule automatically, or you can trigger them manually from the **Actions** tab using "Run workflow".

## Manual trigger

From the GitHub Actions tab, select either workflow and click **Run workflow**. The scripts are idempotent — re-running on the same day won't create duplicate data.

## Attribution

This project uses data from the **Fair Fuel Open Data API** provided by **Service Victoria**, Victorian Government. Data is published with a ~24 hour delay from retailer submissions.

Use of this data is subject to Service Victoria's terms of use.

## Licence

The code in this repository is provided under the [MIT Licence](https://opensource.org/licenses/MIT). The fuel price data itself is subject to Service Victoria's terms.
