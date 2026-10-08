-- Gold dimensions. dim_customer and dim_store keep SCD-2 history (one row per version).

CREATE OR REPLACE TABLE claude_catalog.gold.dim_customer
COMMENT 'Customer dimension, one row per version (SCD-2 from silver)' AS
SELECT customer_sk, customer_id, full_name, email, phone, city, state, segment, signup_date,
       preferred_store_id, effective_from, effective_to, is_current
FROM claude_catalog.silver.customers;

CREATE OR REPLACE TABLE claude_catalog.gold.dim_store
COMMENT 'Store dimension, one row per version (SCD-2 from silver)' AS
SELECT store_sk, store_id, store_name, city, state, region, manager_name, square_feet, open_date,
       effective_from, effective_to, is_current
FROM claude_catalog.silver.stores;

CREATE OR REPLACE TABLE claude_catalog.gold.dim_department
COMMENT 'Department dimension (SCD-1 from silver)' AS
SELECT department_id, department_name, category, manager_name, annual_budget
FROM claude_catalog.silver.departments;

CREATE OR REPLACE TABLE claude_catalog.gold.dim_date
COMMENT 'Calendar dimension covering the order date range' AS
SELECT
  CAST(date_format(d, 'yyyyMMdd') AS INT) AS date_key,
  d                                       AS date,
  year(d)                                 AS year,
  quarter(d)                              AS quarter,
  month(d)                                AS month,
  date_format(d, 'MMMM')                  AS month_name,
  weekofyear(d)                           AS week_of_year,
  dayofweek(d)                            AS day_of_week,
  date_format(d, 'EEEE')                  AS day_name,
  dayofweek(d) IN (1, 7)                  AS is_weekend
FROM (
  SELECT explode(sequence(mn, mx, INTERVAL 1 DAY)) AS d
  FROM (SELECT min(order_date) AS mn, max(order_date) AS mx FROM claude_catalog.silver.orders)
);
