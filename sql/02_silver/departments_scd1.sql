-- silver.departments : SCD Type 1 (changes overwrite the old values, no history).

-- 1) Cleaning + DQ rules in one place. dq_failed_rule IS NULL => row is good.
CREATE OR REPLACE VIEW claude_catalog.silver.vw_departments_clean AS
SELECT
  department_id,
  department_name,
  category,
  manager_name,
  annual_budget,
  sha2(concat_ws('||', department_name, category, manager_name, CAST(annual_budget AS STRING)), 256) AS row_hash,
  CASE
    WHEN department_id IS NULL                       THEN 'null_key'
    WHEN department_name IS NULL OR department_name = '' THEN 'missing_name'
    WHEN annual_budget < 0                           THEN 'negative_budget'
  END AS dq_failed_rule
FROM (
  SELECT
    department_id,
    trim(department_name)  AS department_name,
    initcap(trim(category)) AS category,
    trim(manager_name)     AS manager_name,
    annual_budget
  FROM claude_catalog.raw.departments
);

-- 2) Target table.
CREATE TABLE IF NOT EXISTS claude_catalog.silver.departments (
  department_id   INT NOT NULL,
  department_name STRING,
  category        STRING,
  manager_name    STRING,
  annual_budget   DECIMAL(14,2),
  row_hash        STRING,
  _loaded_at      TIMESTAMP,
  _updated_at     TIMESTAMP,
  _source_table   STRING,
  CONSTRAINT pk_silver_departments PRIMARY KEY (department_id)
) COMMENT 'Silver: departments (SCD Type 1)';

-- 3) SCD-1 upsert: update in place when attributes changed, insert new keys.
MERGE INTO claude_catalog.silver.departments AS t
USING (SELECT * FROM claude_catalog.silver.vw_departments_clean WHERE dq_failed_rule IS NULL) AS s
ON t.department_id = s.department_id
WHEN MATCHED AND t.row_hash <> s.row_hash THEN UPDATE SET
  t.department_name = s.department_name,
  t.category        = s.category,
  t.manager_name    = s.manager_name,
  t.annual_budget   = s.annual_budget,
  t.row_hash        = s.row_hash,
  t._updated_at     = current_timestamp()
WHEN NOT MATCHED THEN INSERT
  (department_id, department_name, category, manager_name, annual_budget, row_hash, _loaded_at, _updated_at, _source_table)
VALUES
  (s.department_id, s.department_name, s.category, s.manager_name, s.annual_budget, s.row_hash,
   current_timestamp(), current_timestamp(), 'raw.departments');
