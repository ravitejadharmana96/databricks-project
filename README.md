# Medallion pipeline on Databricks (`claude_catalog`)

Raw -> Silver (SCD-1 / SCD-2) -> Gold, built on the Serverless Starter Warehouse (`406e144bbc87fee4`) because no cluster exists.

## Layout
```
docs/medallion_plan.txt      original layer plan
scripts/generate_data.py     writes data/source/batch_1  (1,000 rows per table, PK/FK consistent)
scripts/generate_batch2.py   writes data/source/batch_2  (same keys, with changes)
data/source/batch_N/*.csv    source snapshots, uploaded to /Volumes/claude_catalog/raw/landing/batch_N/
sql/00_setup                 schemas + landing volume
sql/01_raw                   raw tables loaded from the chosen batch folder
sql/02_silver                cleaning, DQ rules, SCD-1 and SCD-2 loads
sql/03_gold                  dimensions, fact_orders, aggregates
jobs/medallion_pipeline.json job definition (job id 527613356560453)
sales_dashboard/             Gold Sales Dashboard: build script, JSON definition and its own README
```
Workspace copy of `sql/`: `/Workspace/Users/ravitejadharmana96@gmail.com/claude_medallion/sql/`.

## Layers
| Layer | Schema | Contents |
|---|---|---|
| Raw | `claude_catalog.raw` | departments, stores, customers, orders (snapshot of the batch, PK/FK constraints) |
| Silver | `claude_catalog.silver` | `departments`, `orders` = SCD-1 (overwrite); `stores`, `customers` = SCD-2 (history); `dq_rejects` quarantine |
| Gold | `claude_catalog.gold` | `dim_customer`, `dim_store`, `dim_department`, `dim_date`, `fact_orders`, `agg_*`, `customer_360` |

## SCD behaviour
- **SCD-1** (`MERGE`, update in place): changed department budgets/managers and order statuses replace the old values.
- **SCD-2** (staged-union `MERGE`): a change closes the open version (`is_current = false`, `effective_to` = change date) and inserts a new one. Versions cover `[effective_from, effective_to)`; the open version ends `9999-12-31`.
- The change date comes from `source_updated_date` in the source files.
- Guard: a source row only creates a new version if its `source_updated_date` is newer than the current version's `effective_from`, so replaying an older snapshot cannot rewind history.
- `gold.fact_orders` joins orders to the customer/store version valid on the order date (point-in-time).

## Dashboard
`Gold Sales Dashboard` (ID `01f1c318f3581ae9b3abb00a972269fa`, published, warehouse `406e144bbc87fee4`):
Sales Overview, Stores & Departments, Customers, plus a global Filters page (date, region, category, status, payment).
Details, pages and datasets: [`sales_dashboard/README.md`](sales_dashboard/README.md).
Rebuild and redeploy after editing `sales_dashboard/build_dashboard.py`:
```
python3 sales_dashboard/build_dashboard.py
databricks lakeview update 01f1c318f3581ae9b3abb00a972269fa --serialized-dashboard "$(cat sales_dashboard/gold_sales_dashboard.json)"
databricks lakeview publish 01f1c318f3581ae9b3abb00a972269fa --warehouse-id 406e144bbc87fee4
```
Use `update` on the same ID; `create` would make a new dashboard with a new URL.

## Running
Pipeline: `setup -> raw_load -> silver_* -> silver_dq_rejects -> gold_*`.
The job parameter `batch` (default `batch_1`) picks the source folder. To load the changed snapshot, set the
job parameter default to `batch_2` (the run tool cannot override job parameters) and run the job.
Run `batch_1` first, then `batch_2`.

To start over: drop `claude_catalog.silver.customers` and `claude_catalog.silver.stores` (SCD-2 history cannot
be rebuilt from a later snapshot) and replay batch_1, then batch_2.

## Known results (batch_1 then batch_2)
- Silver customers 1,222 versions / 1,000 current; stores 1,074 versions / 1,000 current.
- Silver orders and departments 1,000 rows each, 0 rows in `dq_rejects`.
- Gold `fact_orders` 1,000 rows, no missing customer/store keys.
