-- silver.orders : SCD Type 1 (status and other changes overwrite the old values, no history).
-- Runs after departments, stores and customers because it validates its foreign keys against them.

CREATE OR REPLACE VIEW claude_catalog.silver.vw_orders_clean AS
SELECT
  o.*,
  year(o.order_date)  AS order_year,
  month(o.order_date) AS order_month,
  o.status IN ('Cancelled', 'Returned') AS is_cancelled_or_returned,
  sha2(concat_ws('||', CAST(o.customer_id AS STRING), CAST(o.store_id AS STRING), CAST(o.department_id AS STRING),
                 CAST(o.order_date AS STRING), o.status, CAST(o.quantity AS STRING), CAST(o.unit_price AS STRING),
                 CAST(o.total_amount AS STRING), o.payment_method), 256) AS row_hash,
  CASE
    WHEN o.order_id IS NULL                                  THEN 'null_key'
    WHEN o.quantity IS NULL OR o.quantity <= 0               THEN 'bad_quantity'
    WHEN o.unit_price IS NULL OR o.unit_price < 0            THEN 'bad_unit_price'
    WHEN o.order_date IS NULL OR o.order_date > current_date() THEN 'bad_order_date'
    WHEN o.status NOT IN ('Completed', 'Shipped', 'Pending', 'Cancelled', 'Returned') OR o.status IS NULL
                                                             THEN 'invalid_status'
    WHEN c.customer_id IS NULL                               THEN 'orphan_customer'
    WHEN s.store_id IS NULL                                  THEN 'orphan_store'
    WHEN d.department_id IS NULL                             THEN 'orphan_department'
  END AS dq_failed_rule
FROM (
  SELECT
    order_id, customer_id, store_id, department_id, order_date,
    initcap(trim(status)) AS status,
    quantity,
    unit_price,
    CAST(quantity * unit_price AS DECIMAL(12,2)) AS total_amount,          -- recomputed from quantity * unit_price
    total_amount <> CAST(quantity * unit_price AS DECIMAL(12,2)) AS is_amount_corrected,
    CASE WHEN lower(trim(payment_method)) = 'paypal' THEN 'PayPal' ELSE initcap(trim(payment_method)) END AS payment_method
  FROM claude_catalog.raw.orders
) o
LEFT JOIN claude_catalog.silver.customers   c ON c.customer_id   = o.customer_id AND c.is_current
LEFT JOIN claude_catalog.silver.stores      s ON s.store_id      = o.store_id    AND s.is_current
LEFT JOIN claude_catalog.silver.departments d ON d.department_id = o.department_id;

CREATE TABLE IF NOT EXISTS claude_catalog.silver.orders (
  order_id                 INT NOT NULL,
  customer_id              INT,
  store_id                 INT,
  department_id            INT,
  order_date               DATE,
  status                   STRING,
  quantity                 INT,
  unit_price               DECIMAL(10,2),
  total_amount             DECIMAL(12,2),
  payment_method           STRING,
  is_amount_corrected      BOOLEAN,
  order_year               INT,
  order_month              INT,
  is_cancelled_or_returned BOOLEAN,
  row_hash                 STRING,
  _loaded_at               TIMESTAMP,
  _updated_at              TIMESTAMP,
  _source_table            STRING,
  CONSTRAINT pk_silver_orders PRIMARY KEY (order_id),
  CONSTRAINT fk_silver_orders_department FOREIGN KEY (department_id) REFERENCES claude_catalog.silver.departments (department_id)
) COMMENT 'Silver: orders (SCD Type 1). Customer/store keys point at SCD-2 tables, validated by DQ rules instead of FKs.';

MERGE INTO claude_catalog.silver.orders AS t
USING (SELECT * FROM claude_catalog.silver.vw_orders_clean WHERE dq_failed_rule IS NULL) AS s
ON t.order_id = s.order_id
WHEN MATCHED AND t.row_hash <> s.row_hash THEN UPDATE SET
  t.customer_id              = s.customer_id,
  t.store_id                 = s.store_id,
  t.department_id            = s.department_id,
  t.order_date               = s.order_date,
  t.status                   = s.status,
  t.quantity                 = s.quantity,
  t.unit_price               = s.unit_price,
  t.total_amount             = s.total_amount,
  t.payment_method           = s.payment_method,
  t.is_amount_corrected      = s.is_amount_corrected,
  t.order_year               = s.order_year,
  t.order_month              = s.order_month,
  t.is_cancelled_or_returned = s.is_cancelled_or_returned,
  t.row_hash                 = s.row_hash,
  t._updated_at              = current_timestamp()
WHEN NOT MATCHED THEN INSERT
  (order_id, customer_id, store_id, department_id, order_date, status, quantity, unit_price, total_amount,
   payment_method, is_amount_corrected, order_year, order_month, is_cancelled_or_returned, row_hash,
   _loaded_at, _updated_at, _source_table)
VALUES
  (s.order_id, s.customer_id, s.store_id, s.department_id, s.order_date, s.status, s.quantity, s.unit_price,
   s.total_amount, s.payment_method, s.is_amount_corrected, s.order_year, s.order_month,
   s.is_cancelled_or_returned, s.row_hash, current_timestamp(), current_timestamp(), 'raw.orders');
