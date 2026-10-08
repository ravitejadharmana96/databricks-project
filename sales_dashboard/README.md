# Gold Sales Dashboard

Databricks AI/BI (Lakeview) dashboard on the gold layer of `claude_catalog.gold`.

| | |
|---|---|
| Dashboard ID | `01f1c318f3581ae9b3abb00a972269fa` |
| Warehouse | Serverless Starter Warehouse `406e144bbc87fee4` |
| Workspace path | `/Users/ravitejadharmana96@gmail.com/claude_medallion/dashboards/` |
| Published | yes (viewers need access to `claude_catalog.gold` and the warehouse) |

## Files
| File | Purpose |
|---|---|
| `build_dashboard.py` | generates the dashboard JSON (datasets, 3 pages + filters, theme) |
| `gold_sales_dashboard.json` | generated dashboard definition, ready to deploy |

## Pages
| Page | Contents |
|---|---|
| Sales Overview | KPIs (net revenue, orders, avg order value, cancel + return rate), monthly gross vs net revenue, order status mix, revenue by region / category / payment method |
| Stores & Departments | top 15 stores, top 10 departments, cancel + return rate by region |
| Customers | customers and lifetime value by RFM segment, revenue and avg order value by segment at order time (uses the SCD-2 history), top 20 customers |
| Filters (global) | order date, region, department category, order status, payment method |

## Datasets
| Dataset | Source |
|---|---|
| `ds_orders` | `gold.fact_orders` joined to `dim_store` (current region), `dim_department`, `dim_customer` (segment at order time); holds the measures Net Revenue, Gross Revenue, Orders, Avg Order Value, Cancel + Return Rate |
| `ds_stores` | top 15 rows of `gold.agg_store_performance` |
| `ds_depts` | top 10 rows of `gold.agg_department_performance` |
| `ds_customers` | `gold.customer_360` |
| `ds_top_customers` | top 20 rows of `gold.customer_360` by lifetime value |

Store, department and customer-segment widgets read pre-aggregated gold tables, so only the filters that exist in
their dataset apply to them (region for stores, category for departments).

## Rebuild and redeploy
Run from the repository root. Use `update` on the same ID; `create` would make a new dashboard with a new URL.

```bash
python3 sales_dashboard/build_dashboard.py
databricks lakeview update 01f1c318f3581ae9b3abb00a972269fa \
  --serialized-dashboard "$(cat sales_dashboard/gold_sales_dashboard.json)"
databricks lakeview publish 01f1c318f3581ae9b3abb00a972269fa --warehouse-id 406e144bbc87fee4
```

## Prerequisites
The gold tables must exist and be current: run the `medallion_pipeline` job first (see the root `README.md`).
