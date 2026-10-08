-- gold.fact_orders : one row per order.
-- Point-in-time join: each order is linked to the customer/store VERSION that was valid on its order_date.

CREATE OR REPLACE TABLE claude_catalog.gold.fact_orders
COMMENT 'Order fact table with point-in-time customer and store keys' AS
SELECT
  o.order_id,
  o.order_date,
  CAST(date_format(o.order_date, 'yyyyMMdd') AS INT) AS date_key,
  c.customer_sk,
  s.store_sk,
  o.department_id,
  o.status,
  o.payment_method,
  o.quantity,
  o.unit_price,
  o.total_amount                                      AS gross_amount,
  CASE WHEN o.is_cancelled_or_returned THEN CAST(0 AS DECIMAL(12,2)) ELSE o.total_amount END AS net_amount,
  NOT o.is_cancelled_or_returned                      AS is_net_revenue
FROM claude_catalog.silver.orders o
LEFT JOIN claude_catalog.silver.customers c
  ON c.customer_id = o.customer_id AND o.order_date >= c.effective_from AND o.order_date < c.effective_to
LEFT JOIN claude_catalog.silver.stores s
  ON s.store_id = o.store_id AND o.order_date >= s.effective_from AND o.order_date < s.effective_to;
