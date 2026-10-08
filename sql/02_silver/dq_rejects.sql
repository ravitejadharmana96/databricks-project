-- silver.dq_rejects : quarantine of raw rows that failed a rule in the silver cleaning views.
-- Rebuilt each run, so it always shows the rows currently failing.
CREATE OR REPLACE TABLE claude_catalog.silver.dq_rejects
COMMENT 'Rows rejected by silver data-quality rules (current snapshot)' AS
SELECT 'departments' AS source_table, CAST(department_id AS STRING) AS business_key, dq_failed_rule AS rule_name,
       current_timestamp() AS rejected_at
FROM claude_catalog.silver.vw_departments_clean WHERE dq_failed_rule IS NOT NULL
UNION ALL
SELECT 'stores', CAST(store_id AS STRING), dq_failed_rule, current_timestamp()
FROM claude_catalog.silver.vw_stores_clean WHERE dq_failed_rule IS NOT NULL
UNION ALL
SELECT 'customers', CAST(customer_id AS STRING), dq_failed_rule, current_timestamp()
FROM claude_catalog.silver.vw_customers_clean WHERE dq_failed_rule IS NOT NULL
UNION ALL
SELECT 'orders', CAST(order_id AS STRING), dq_failed_rule, current_timestamp()
FROM claude_catalog.silver.vw_orders_clean WHERE dq_failed_rule IS NOT NULL;
