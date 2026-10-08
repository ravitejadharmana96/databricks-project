"""Build dashboards/gold_sales_dashboard.json (Databricks AI/BI dashboard on claude_catalog.gold)."""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "dashboards" / "gold_sales_dashboard.json"
G = "claude_catalog.gold"

# Okabe-Ito based, colour-blind safe. Semantic status colours are pinned as literal hex.
PALETTE = ["#0072B2", "#E69F00", "#009E73", "#CC79A7", "#D55E00", "#56B4E9", "#F0E442"]
STATUS_COLORS = [("Completed", "#009E73"), ("Shipped", "#0072B2"), ("Pending", "#56B4E9"),
                 ("Cancelled", "#D55E00"), ("Returned", "#CC79A7")]
CUR = {"type": "number-currency", "currencyCode": "USD", "abbreviation": "compact",
       "decimalPlaces": {"type": "max", "places": 2}}
PCT = {"type": "number-percent", "decimalPlaces": {"type": "max", "places": 1}}

# ---------------------------------------------------------------- datasets
datasets = [
    {
        "name": "ds_orders",
        "displayName": "Orders (gold.fact_orders + dims)",
        "queryLines": [
            "SELECT f.order_id, f.order_date, f.status, f.payment_method, f.quantity,\n",
            "       f.gross_amount, f.net_amount, f.is_net_revenue,\n",
            "       cur.region, cur.store_name, d.category, d.department_name,\n",
            "       c.segment AS segment_at_order\n",
            f"FROM {G}.fact_orders f\n",
            f"JOIN {G}.dim_store v   ON v.store_sk = f.store_sk\n",
            f"JOIN {G}.dim_store cur ON cur.store_id = v.store_id AND cur.is_current\n",
            f"JOIN {G}.dim_department d ON d.department_id = f.department_id\n",
            f"JOIN {G}.dim_customer c ON c.customer_sk = f.customer_sk",
        ],
        "columns": [
            {"displayName": "Net Revenue", "description": "Revenue excluding cancelled and returned orders",
             "expression": "SUM(`net_amount`)"},
            {"displayName": "Gross Revenue", "description": "Revenue including cancelled and returned orders",
             "expression": "SUM(`gross_amount`)"},
            {"displayName": "Orders", "description": "Number of orders", "expression": "COUNT(`order_id`)"},
            {"displayName": "Avg Order Value", "description": "Net revenue per non-cancelled, non-returned order",
             "expression": "SUM(`net_amount`) / NULLIF(SUM(CASE WHEN `is_net_revenue` THEN 1 ELSE 0 END), 0)"},
            {"displayName": "Cancel + Return Rate", "description": "Share of orders cancelled or returned",
             "expression": "SUM(CASE WHEN `status` IN ('Cancelled', 'Returned') THEN 1 ELSE 0 END) * 1.0 / COUNT(`order_id`)"},
        ],
    },
    {
        "name": "ds_stores",
        "displayName": "Top 15 stores",
        "queryLines": [
            "SELECT store_id, store_name, city, state, region, orders, net_revenue, avg_order_value, revenue_rank\n",
            f"FROM {G}.agg_store_performance\n",
            "ORDER BY revenue_rank\n",
            "LIMIT 15",
        ],
    },
    {
        "name": "ds_depts",
        "displayName": "Top 10 departments",
        "queryLines": [
            "SELECT department_name, category, orders, units, net_revenue, revenue_rank\n",
            f"FROM {G}.agg_department_performance\n",
            "ORDER BY revenue_rank\n",
            "LIMIT 10",
        ],
    },
    {
        "name": "ds_customers",
        "displayName": "Customer 360",
        "queryLines": [
            "SELECT customer_id, full_name, city, state, segment, total_orders, lifetime_value,\n",
            "       last_order_date, days_since_last_order, rfm_segment\n",
            f"FROM {G}.customer_360",
        ],
    },
    {
        "name": "ds_top_customers",
        "displayName": "Top 20 customers",
        "queryLines": [
            "SELECT customer_id, full_name, city, state, segment, total_orders, lifetime_value,\n",
            "       last_order_date, rfm_segment\n",
            f"FROM {G}.customer_360\n",
            "WHERE total_orders > 0\n",
            "ORDER BY lifetime_value DESC\n",
            "LIMIT 20",
        ],
    },
]


# ---------------------------------------------------------------- widget helpers
def f(name, expr=None):
    return {"name": name, "expression": expr or f"`{name}`"}


def measure(name):
    return f"measure({name})", f"MEASURE(`{name}`)"


def mfield(name):
    n, e = measure(name)
    return {"name": n, "expression": e}


def pos(x, y, w, h):
    return {"x": x, "y": y, "width": w, "height": h}


def text(name, line, x, y, w, h):
    return {"widget": {"name": name, "multilineTextboxSpec": {"lines": [line]}}, "position": pos(x, y, w, h)}


def query(ds, fields, disaggregated=False):
    return [{"name": "main_query", "query": {"datasetName": ds, "fields": fields, "disaggregated": disaggregated}}]


def counter(name, title, ds, field, display, x, y, fmt=None):
    value = {"fieldName": measure(field)[0], "displayName": display}
    if fmt:
        value["format"] = fmt
    return {"widget": {"name": name, "queries": query(ds, [mfield(field)]),
                       "spec": {"version": 2, "widgetType": "counter", "encodings": {"value": value},
                                "frame": {"title": title, "showTitle": True}}},
            "position": pos(x, y, 3, 3)}


def table(name, title, ds, cols, x, y, w, h):
    return {"widget": {"name": name,
                       "queries": query(ds, [f(c["fieldName"]) for c in cols], disaggregated=True),
                       "spec": {"version": 2, "widgetType": "table", "encodings": {"columns": cols},
                                "frame": {"showTitle": True, "title": title}}},
            "position": pos(x, y, w, h)}


def pie(name, title, ds, dim, dim_name, meas, meas_name, x, y, w, h, mappings=None, fmt=None):
    color = {"fieldName": dim, "displayName": dim_name, "scale": {"type": "categorical"}}
    if mappings:
        color["scale"]["mappings"] = [{"value": v, "color": c} for v, c in mappings]
    angle = {"fieldName": measure(meas)[0], "displayName": meas_name, "scale": {"type": "quantitative"}}
    return {"widget": {"name": name, "queries": query(ds, [f(dim), mfield(meas)]),
                       "spec": {"version": 3, "widgetType": "pie",
                                "encodings": {"angle": angle, "color": color, "label": {"show": True}},
                                "frame": {"showTitle": True, "title": title}}},
            "position": pos(x, y, w, h)}


def bar(name, title, ds, dim_field, dim_name, meas_field, meas_name, x, y, w, h,
        horizontal=False, fmt=None, sort=None, count_field=False):
    dim = {"fieldName": dim_field["name"], "displayName": dim_name, "scale": {"type": "categorical"}}
    if sort:
        dim["scale"]["sort"] = sort
    val = {"fieldName": meas_field["name"], "displayName": meas_name, "scale": {"type": "quantitative"}}
    if fmt:
        val["format"] = fmt
    enc = {"x": val, "y": dim} if horizontal else {"x": dim, "y": val}
    return {"widget": {"name": name, "queries": query(ds, [dim_field, meas_field]),
                       "spec": {"version": 3, "widgetType": "bar", "encodings": enc,
                                "frame": {"showTitle": True, "title": title}}},
            "position": pos(x, y, w, h)}


def flt(name, title, widget_type, bindings, x, y):
    """bindings: list of (dataset, field). One query per dataset so the filter hits all of them."""
    qs, fs = [], []
    for i, (ds, field) in enumerate(bindings):
        qn = f"q_{name}_{i}"
        qs.append({"name": qn, "query": {"datasetName": ds, "fields": [f(field)], "disaggregated": False}})
        fs.append({"fieldName": field, "displayName": title, "queryName": qn})
    return {"widget": {"name": name, "queries": qs,
                       "spec": {"version": 2, "widgetType": widget_type, "encodings": {"fields": fs},
                                "frame": {"showTitle": True, "title": title}}},
            "position": pos(x, y, 4, 2)}


# ---------------------------------------------------------------- page 1: sales overview
monthly = {
    "widget": {
        "name": "monthly-revenue",
        "queries": query("ds_orders", [f('monthly(order_date)', 'DATE_TRUNC("MONTH", `order_date`)'),
                                       mfield("Net Revenue"), mfield("Gross Revenue")]),
        "spec": {"version": 3, "widgetType": "line",
                 "encodings": {
                     "x": {"fieldName": "monthly(order_date)", "scale": {"type": "temporal"}, "displayName": "Month"},
                     "y": {"scale": {"type": "quantitative"},
                           "fields": [{"fieldName": "measure(Net Revenue)", "displayName": "Net revenue", "format": CUR},
                                      {"fieldName": "measure(Gross Revenue)", "displayName": "Gross revenue",
                                       "format": CUR}]}},
                 "frame": {"showTitle": True, "title": "Monthly revenue: gross vs net (the gap is lost revenue)"}}},
    "position": pos(0, 6, 8, 6),
}

page_overview = {
    "name": "overview", "displayName": "Sales Overview", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1",
    "layout": [
        text("ov-title", "# Sales Overview", 0, 0, 12, 1),
        text("ov-story", "Where does revenue come from, and where do we lose it? **Net revenue** excludes cancelled "
                         "and returned orders, so the gap between the gross and net lines is revenue lost. "
                         "Use the Filters page to slice by date, region, category, status or payment method.",
             0, 1, 12, 2),
        counter("kpi-net", "Net Revenue", "ds_orders", "Net Revenue", "Net revenue", 0, 3, CUR),
        counter("kpi-orders", "Orders", "ds_orders", "Orders", "Orders", 3, 3),
        counter("kpi-aov", "Avg Order Value", "ds_orders", "Avg Order Value", "Avg order value", 6, 3, CUR),
        counter("kpi-lost", "Cancel + Return Rate", "ds_orders", "Cancel + Return Rate", "Cancel + return rate", 9, 3, PCT),
        monthly,
        pie("status-mix", "Order status mix", "ds_orders", "status", "Status", "Orders", "Orders", 8, 6, 4, 6,
            mappings=STATUS_COLORS),
        bar("rev-region", "Net revenue by region", "ds_orders", f("region"), "Region", mfield("Net Revenue"),
            "Net revenue", 0, 12, 4, 6, fmt=CUR, sort={"by": "value"}),
        bar("rev-category", "Net revenue by department category", "ds_orders", f("category"), "Category",
            mfield("Net Revenue"), "Net revenue", 4, 12, 4, 6, horizontal=True, fmt=CUR, sort={"by": "value"}),
        pie("rev-payment", "Net revenue by payment method", "ds_orders", "payment_method", "Payment method",
            "Net Revenue", "Net revenue", 8, 12, 4, 6),
    ],
}

# ---------------------------------------------------------------- page 2: stores and departments
store_cols = [
    {"fieldName": "revenue_rank", "displayName": "Rank"},
    {"fieldName": "store_name", "displayName": "Store"},
    {"fieldName": "city", "displayName": "City"},
    {"fieldName": "region", "displayName": "Region"},
    {"fieldName": "orders", "displayName": "Orders"},
    {"fieldName": "net_revenue", "displayName": "Net revenue", "format": CUR},
    {"fieldName": "avg_order_value", "displayName": "Avg order value", "format": CUR},
]
page_stores = {
    "name": "stores", "displayName": "Stores & Departments", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1",
    "layout": [
        text("st-title", "# Stores & Departments", 0, 0, 12, 1),
        text("st-story", "Top performers by net revenue, and where cancellations and returns concentrate. "
                         "The store and department rankings come from the gold aggregate tables, so only the region "
                         "and category filters apply to them; the cancel + return chart follows every filter.",
             0, 1, 12, 2),
        table("top-stores", "Top 15 stores by net revenue", "ds_stores", store_cols, 0, 3, 12, 7),
        bar("top-depts", "Top 10 departments by net revenue", "ds_depts", f("department_name"), "Department",
            f("net_revenue", "`net_revenue`"), "Net revenue", 0, 10, 6, 6, horizontal=True, fmt=CUR),
        bar("rate-region", "Cancel + return rate by region", "ds_orders", f("region"), "Region",
            mfield("Cancel + Return Rate"), "Cancel + return rate", 6, 10, 6, 6, fmt=PCT),
    ],
}
# ds_depts is pre-aggregated, so its widget reads the column directly (not a MEASURE)
dept_widget = page_stores["layout"][3]["widget"]
dept_widget["queries"] = query("ds_depts", [f("department_name"), f("net_revenue")], disaggregated=True)

# ---------------------------------------------------------------- page 3: customers
cust_cols = [
    {"fieldName": "full_name", "displayName": "Customer"},
    {"fieldName": "city", "displayName": "City"},
    {"fieldName": "state", "displayName": "State"},
    {"fieldName": "segment", "displayName": "Segment"},
    {"fieldName": "rfm_segment", "displayName": "RFM segment"},
    {"fieldName": "total_orders", "displayName": "Orders"},
    {"fieldName": "lifetime_value", "displayName": "Lifetime value", "format": CUR},
    {"fieldName": "last_order_date", "displayName": "Last order"},
]
RFM_ORDER = {"by": "custom-order", "orderedValues": ["Champion", "Loyal", "At-risk", "Lost", "No Orders"]}
SEG_ORDER = {"by": "custom-order", "orderedValues": ["Regular", "Premium", "VIP"]}
page_customers = {
    "name": "customers", "displayName": "Customers", "pageType": "PAGE_TYPE_CANVAS", "layoutVersion": "GRID_V1",
    "layout": [
        text("cu-title", "# Customers", 0, 0, 12, 1),
        text("cu-story", "Who buys, and who is drifting away? RFM segments use each customer's most recent order. "
                         "The two charts on the right use the customer's segment **at the time of the order** "
                         "(point-in-time from the SCD-2 history), so an upgrade from Regular to Premium does not "
                         "rewrite past orders. Only the date, region, category, status and payment filters apply to "
                         "those two charts.",
             0, 1, 12, 2),
        bar("rfm-customers", "Customers by RFM segment", "ds_customers", f("rfm_segment"), "RFM segment",
            {"name": "count(customer_id)", "expression": "COUNT(`customer_id`)"}, "Customers", 0, 3, 6, 5,
            sort=RFM_ORDER),
        bar("seg-revenue", "Net revenue by segment at order time", "ds_orders", f("segment_at_order"), "Segment",
            mfield("Net Revenue"), "Net revenue", 6, 3, 6, 5, fmt=CUR, sort=SEG_ORDER),
        bar("rfm-ltv", "Lifetime value by RFM segment", "ds_customers", f("rfm_segment"), "RFM segment",
            {"name": "sum(lifetime_value)", "expression": "SUM(`lifetime_value`)"}, "Lifetime value", 0, 8, 6, 5,
            fmt=CUR, sort=RFM_ORDER),
        bar("seg-aov", "Avg order value by segment at order time", "ds_orders", f("segment_at_order"), "Segment",
            mfield("Avg Order Value"), "Avg order value", 6, 8, 6, 5, fmt=CUR, sort=SEG_ORDER),
        table("top-customers", "Top 20 customers by lifetime value", "ds_top_customers", cust_cols, 0, 13, 12, 7),
    ],
}

# ---------------------------------------------------------------- global filters
page_filters = {
    "name": "filters", "displayName": "Filters", "pageType": "PAGE_TYPE_GLOBAL_FILTERS", "layoutVersion": "GRID_V1",
    "layout": [
        flt("flt-date", "Order date", "filter-date-range-picker", [("ds_orders", "order_date")], 0, 0),
        flt("flt-region", "Region", "filter-multi-select", [("ds_orders", "region"), ("ds_stores", "region")], 4, 0),
        flt("flt-category", "Department category", "filter-multi-select",
            [("ds_orders", "category"), ("ds_depts", "category")], 8, 0),
        flt("flt-status", "Order status", "filter-multi-select", [("ds_orders", "status")], 0, 2),
        flt("flt-payment", "Payment method", "filter-multi-select", [("ds_orders", "payment_method")], 4, 2),
    ],
}

dashboard = {
    "datasets": datasets,
    "pages": [page_overview, page_stores, page_customers, page_filters],
    "uiSettings": {"theme": {
        "canvasBackgroundColor": {"light": "#FCFCFC", "dark": "#1F272D"},
        "widgetBackgroundColor": {"light": "#FFFFFF", "dark": "#11171C"},
        "widgetBorderColor": {"light": "#FFFFFF", "dark": "#11171C"},
        "fontColor": {"light": "#11171C", "dark": "#E8ECF0"},
        "selectionColor": {"light": "#2272B4", "dark": "#8ACAFF"},
        "visualizationColors": PALETTE,
        "widgetHeaderAlignment": "LEFT",
    }},
}

OUT.parent.mkdir(exist_ok=True)
OUT.write_text(json.dumps(dashboard, indent=2))
print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
