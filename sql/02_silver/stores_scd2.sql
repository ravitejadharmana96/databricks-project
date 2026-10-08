-- silver.stores : SCD Type 2 (every change creates a new version; old version is closed, never overwritten).
-- Version validity is the half-open interval [effective_from, effective_to). Open version: effective_to = 9999-12-31.

CREATE OR REPLACE VIEW claude_catalog.silver.vw_stores_clean AS
SELECT
  store_id, store_name, city, state, region, manager_name, square_feet, open_date, source_updated_date,
  sha2(concat_ws('||', store_name, city, state, region, manager_name, CAST(square_feet AS STRING)), 256) AS row_hash,
  CASE
    WHEN store_id IS NULL                                   THEN 'null_key'
    WHEN region NOT IN ('East', 'South', 'Midwest', 'West') OR region IS NULL THEN 'invalid_region'
    WHEN square_feet IS NULL OR square_feet <= 0            THEN 'bad_square_feet'
    WHEN open_date > current_date()                         THEN 'future_open_date'
    WHEN source_updated_date IS NULL                        THEN 'missing_source_date'
  END AS dq_failed_rule
FROM (
  SELECT
    store_id,
    trim(store_name)        AS store_name,
    initcap(trim(city))     AS city,
    upper(trim(state))      AS state,
    initcap(trim(region))   AS region,
    trim(manager_name)      AS manager_name,
    square_feet, open_date, source_updated_date
  FROM claude_catalog.raw.stores
);

CREATE TABLE IF NOT EXISTS claude_catalog.silver.stores (
  store_sk            BIGINT GENERATED ALWAYS AS IDENTITY,
  store_id            INT NOT NULL,
  store_name          STRING,
  city                STRING,
  state               STRING,
  region              STRING,
  manager_name        STRING,
  square_feet         INT,
  open_date           DATE,
  row_hash            STRING,
  effective_from      DATE NOT NULL,
  effective_to        DATE NOT NULL,
  is_current          BOOLEAN NOT NULL,
  _loaded_at          TIMESTAMP,
  _source_table       STRING,
  CONSTRAINT pk_silver_stores PRIMARY KEY (store_sk)
) COMMENT 'Silver: stores (SCD Type 2)';

-- Staged-union MERGE:
--   row 1 per source row (merge_key = store_id): matches the open version -> close it (if attributes changed),
--                                               or inserts a brand-new store.
--   row 2 only for changed stores (merge_key = NULL): never matches -> inserts the new version.
MERGE INTO claude_catalog.silver.stores AS t
USING (
  WITH src AS (SELECT * FROM claude_catalog.silver.vw_stores_clean WHERE dq_failed_rule IS NULL)
  SELECT s.store_id AS merge_key, s.* FROM src s
  UNION ALL
  SELECT CAST(NULL AS INT) AS merge_key, s.*
  FROM src s
  JOIN claude_catalog.silver.stores c
    ON c.store_id = s.store_id AND c.is_current AND c.row_hash <> s.row_hash
   AND s.source_updated_date > c.effective_from
) AS m
ON t.store_id = m.merge_key AND t.is_current = true
-- Guard: only close a version for a strictly newer change, so replaying an older snapshot cannot rewind history.
WHEN MATCHED AND t.row_hash <> m.row_hash AND m.source_updated_date > t.effective_from THEN UPDATE SET
  t.is_current   = false,
  t.effective_to = m.source_updated_date
WHEN NOT MATCHED THEN INSERT
  (store_id, store_name, city, state, region, manager_name, square_feet, open_date, row_hash,
   effective_from, effective_to, is_current, _loaded_at, _source_table)
VALUES
  (m.store_id, m.store_name, m.city, m.state, m.region, m.manager_name, m.square_feet, m.open_date, m.row_hash,
   m.source_updated_date, DATE'9999-12-31', true, current_timestamp(), 'raw.stores');
