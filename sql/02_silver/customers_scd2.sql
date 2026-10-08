-- silver.customers : SCD Type 2 (segment upgrades, relocations, preferred-store changes keep full history).
-- Runs after silver.stores because preferred_store_id is validated against current stores.

CREATE OR REPLACE VIEW claude_catalog.silver.vw_customers_clean AS
SELECT
  c.customer_id, c.first_name, c.last_name, c.full_name, c.email, c.phone, c.city, c.state, c.segment,
  c.signup_date, c.preferred_store_id, c.source_updated_date,
  sha2(concat_ws('||', c.first_name, c.last_name, c.email, c.phone, c.city, c.state, c.segment,
                 CAST(c.preferred_store_id AS STRING)), 256) AS row_hash,
  CASE
    WHEN c.customer_id IS NULL                              THEN 'null_key'
    WHEN c.email IS NULL OR c.email NOT LIKE '%@%.%'        THEN 'invalid_email'
    WHEN c.signup_date > current_date()                     THEN 'future_signup_date'
    WHEN c.source_updated_date IS NULL                      THEN 'missing_source_date'
    WHEN s.store_id IS NULL                                 THEN 'orphan_preferred_store'
  END AS dq_failed_rule
FROM (
  SELECT
    customer_id,
    initcap(trim(first_name)) AS first_name,
    initcap(trim(last_name))  AS last_name,
    concat_ws(' ', initcap(trim(first_name)), initcap(trim(last_name))) AS full_name,
    lower(trim(email))        AS email,
    -- normalize any phone with 11 digits starting with 1 to +1-XXX-XXX-XXXX
    CASE WHEN length(p.digits) = 11 AND p.digits LIKE '1%'
         THEN concat('+1-', substr(p.digits, 2, 3), '-', substr(p.digits, 5, 3), '-', substr(p.digits, 8, 4))
         ELSE phone END       AS phone,
    initcap(trim(city))       AS city,
    upper(trim(state))        AS state,
    CASE WHEN upper(trim(segment)) = 'VIP' THEN 'VIP' ELSE initcap(trim(segment)) END AS segment,
    signup_date, preferred_store_id, source_updated_date
  FROM (SELECT *, regexp_replace(phone, '[^0-9]', '') AS digits FROM claude_catalog.raw.customers) p
) c
LEFT JOIN claude_catalog.silver.stores s ON s.store_id = c.preferred_store_id AND s.is_current;

CREATE TABLE IF NOT EXISTS claude_catalog.silver.customers (
  customer_sk         BIGINT GENERATED ALWAYS AS IDENTITY,
  customer_id         INT NOT NULL,
  first_name          STRING,
  last_name           STRING,
  full_name           STRING,
  email               STRING,
  phone               STRING,
  city                STRING,
  state               STRING,
  segment             STRING,
  signup_date         DATE,
  preferred_store_id  INT,
  row_hash            STRING,
  effective_from      DATE NOT NULL,
  effective_to        DATE NOT NULL,
  is_current          BOOLEAN NOT NULL,
  _loaded_at          TIMESTAMP,
  _source_table       STRING,
  CONSTRAINT pk_silver_customers PRIMARY KEY (customer_sk)
) COMMENT 'Silver: customers (SCD Type 2)';

MERGE INTO claude_catalog.silver.customers AS t
USING (
  WITH src AS (SELECT * FROM claude_catalog.silver.vw_customers_clean WHERE dq_failed_rule IS NULL)
  SELECT s.customer_id AS merge_key, s.* FROM src s
  UNION ALL
  SELECT CAST(NULL AS INT) AS merge_key, s.*
  FROM src s
  JOIN claude_catalog.silver.customers c
    ON c.customer_id = s.customer_id AND c.is_current AND c.row_hash <> s.row_hash
   AND s.source_updated_date > c.effective_from
) AS m
ON t.customer_id = m.merge_key AND t.is_current = true
-- Guard: only close a version for a strictly newer change, so replaying an older snapshot cannot rewind history.
WHEN MATCHED AND t.row_hash <> m.row_hash AND m.source_updated_date > t.effective_from THEN UPDATE SET
  t.is_current   = false,
  t.effective_to = m.source_updated_date
WHEN NOT MATCHED THEN INSERT
  (customer_id, first_name, last_name, full_name, email, phone, city, state, segment, signup_date,
   preferred_store_id, row_hash, effective_from, effective_to, is_current, _loaded_at, _source_table)
VALUES
  (m.customer_id, m.first_name, m.last_name, m.full_name, m.email, m.phone, m.city, m.state, m.segment,
   m.signup_date, m.preferred_store_id, m.row_hash, m.source_updated_date, DATE'9999-12-31', true,
   current_timestamp(), 'raw.customers');
