-- Gold aggregates: ready for dashboards and ad-hoc analysis.

CREATE OR REPLACE TABLE claude_catalog.gold.agg_daily_sales
COMMENT 'Daily orders and revenue' AS
SELECT order_date,
       COUNT(*)                                   AS orders,
       count_if(is_net_revenue)                   AS net_orders,
       SUM(gross_amount)                          AS gross_revenue,
       SUM(net_amount)                            AS net_revenue,
       ROUND(SUM(net_amount) / NULLIF(count_if(is_net_revenue), 0), 2) AS avg_order_value
FROM claude_catalog.gold.fact_orders
GROUP BY order_date;

CREATE OR REPLACE TABLE claude_catalog.gold.agg_monthly_revenue
COMMENT 'Monthly net revenue with month-over-month growth' AS
SELECT month_start, orders, net_revenue,
       LAG(net_revenue) OVER (ORDER BY month_start) AS prev_month_revenue,
       ROUND((net_revenue - LAG(net_revenue) OVER (ORDER BY month_start))
             / NULLIF(LAG(net_revenue) OVER (ORDER BY month_start), 0) * 100, 2) AS mom_growth_pct
FROM (
  SELECT date_trunc('month', order_date) AS month_start, COUNT(*) AS orders, SUM(net_amount) AS net_revenue
  FROM claude_catalog.gold.fact_orders
  GROUP BY date_trunc('month', order_date)
);

CREATE OR REPLACE TABLE claude_catalog.gold.agg_store_performance
COMMENT 'Revenue by store (current store attributes) with rank' AS
SELECT cur.store_id, cur.store_name, cur.city, cur.state, cur.region, cur.manager_name,
       COUNT(*)                         AS orders,
       SUM(f.net_amount)                AS net_revenue,
       ROUND(SUM(f.net_amount) / NULLIF(count_if(f.is_net_revenue), 0), 2) AS avg_order_value,
       RANK() OVER (ORDER BY SUM(f.net_amount) DESC) AS revenue_rank
FROM claude_catalog.gold.fact_orders f
JOIN claude_catalog.gold.dim_store v   ON v.store_sk = f.store_sk
JOIN claude_catalog.gold.dim_store cur ON cur.store_id = v.store_id AND cur.is_current
GROUP BY cur.store_id, cur.store_name, cur.city, cur.state, cur.region, cur.manager_name;

CREATE OR REPLACE TABLE claude_catalog.gold.agg_department_performance
COMMENT 'Revenue and units by department' AS
SELECT d.department_id, d.department_name, d.category,
       COUNT(*)            AS orders,
       SUM(f.quantity)     AS units,
       SUM(f.net_amount)   AS net_revenue,
       RANK() OVER (ORDER BY SUM(f.net_amount) DESC) AS revenue_rank
FROM claude_catalog.gold.fact_orders f
JOIN claude_catalog.gold.dim_department d ON d.department_id = f.department_id
GROUP BY d.department_id, d.department_name, d.category;

CREATE OR REPLACE TABLE claude_catalog.gold.customer_360
COMMENT 'One row per customer (current version): lifetime value, recency and RFM-style segment' AS
WITH o AS (
  SELECT dc.customer_id, f.*
  FROM claude_catalog.gold.fact_orders f
  JOIN claude_catalog.gold.dim_customer dc ON dc.customer_sk = f.customer_sk
),
m AS (
  SELECT customer_id,
         COUNT(*)                 AS total_orders,
         SUM(net_amount)          AS lifetime_value,
         MIN(order_date)          AS first_order_date,
         MAX(order_date)          AS last_order_date
  FROM o GROUP BY customer_id
),
asof AS (SELECT max(order_date) AS as_of_date FROM claude_catalog.gold.fact_orders)
SELECT c.customer_id, c.full_name, c.email, c.city, c.state, c.segment, c.preferred_store_id,
       datediff(asof.as_of_date, c.signup_date)                 AS tenure_days,
       COALESCE(m.total_orders, 0)                              AS total_orders,
       COALESCE(m.lifetime_value, 0)                            AS lifetime_value,
       m.first_order_date, m.last_order_date,
       datediff(asof.as_of_date, m.last_order_date)             AS days_since_last_order,
       CASE
         WHEN m.total_orders IS NULL                                                   THEN 'No Orders'
         WHEN datediff(asof.as_of_date, m.last_order_date) <= 90 AND m.total_orders >= 2 THEN 'Champion'
         WHEN datediff(asof.as_of_date, m.last_order_date) <= 90                       THEN 'Loyal'
         WHEN datediff(asof.as_of_date, m.last_order_date) <= 270                      THEN 'At-risk'
         ELSE 'Lost'
       END AS rfm_segment,
       asof.as_of_date
FROM claude_catalog.gold.dim_customer c
CROSS JOIN asof
LEFT JOIN m ON m.customer_id = c.customer_id
WHERE c.is_current;

CREATE OR REPLACE TABLE claude_catalog.gold.agg_order_status
COMMENT 'Order status mix and cancellation/return rates by store and by department' AS
SELECT 'store' AS dimension_type, CAST(cur.store_id AS STRING) AS dimension_id, cur.store_name AS dimension_name,
       COUNT(*) AS orders,
       count_if(f.status = 'Cancelled') AS cancelled,
       count_if(f.status = 'Returned')  AS returned,
       ROUND(count_if(f.status = 'Cancelled') * 100.0 / COUNT(*), 2) AS cancel_rate_pct,
       ROUND(count_if(f.status = 'Returned')  * 100.0 / COUNT(*), 2) AS return_rate_pct
FROM claude_catalog.gold.fact_orders f
JOIN claude_catalog.gold.dim_store v   ON v.store_sk = f.store_sk
JOIN claude_catalog.gold.dim_store cur ON cur.store_id = v.store_id AND cur.is_current
GROUP BY cur.store_id, cur.store_name
UNION ALL
SELECT 'department', CAST(d.department_id AS STRING), d.department_name,
       COUNT(*),
       count_if(f.status = 'Cancelled'),
       count_if(f.status = 'Returned'),
       ROUND(count_if(f.status = 'Cancelled') * 100.0 / COUNT(*), 2),
       ROUND(count_if(f.status = 'Returned')  * 100.0 / COUNT(*), 2)
FROM claude_catalog.gold.fact_orders f
JOIN claude_catalog.gold.dim_department d ON d.department_id = f.department_id
GROUP BY d.department_id, d.department_name;

CREATE OR REPLACE TABLE claude_catalog.gold.agg_payment_methods
COMMENT 'Payment method mix and revenue share' AS
SELECT payment_method,
       COUNT(*)          AS orders,
       SUM(net_amount)   AS net_revenue,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)        AS order_share_pct,
       ROUND(SUM(net_amount) * 100.0 / SUM(SUM(net_amount)) OVER (), 2) AS revenue_share_pct
FROM claude_catalog.gold.fact_orders
GROUP BY payment_method;

CREATE OR REPLACE TABLE claude_catalog.gold.agg_segment_performance
COMMENT 'Spend by customer segment AS OF the order date (uses SCD-2 history)' AS
SELECT dc.segment AS segment_at_order_time,
       COUNT(*)                         AS orders,
       COUNT(DISTINCT dc.customer_id)   AS customers,
       SUM(f.net_amount)                AS net_revenue,
       ROUND(SUM(f.net_amount) / NULLIF(count_if(f.is_net_revenue), 0), 2) AS avg_order_value
FROM claude_catalog.gold.fact_orders f
JOIN claude_catalog.gold.dim_customer dc ON dc.customer_sk = f.customer_sk
GROUP BY dc.segment;
