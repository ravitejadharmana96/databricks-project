-- Medallion schemas inside claude_catalog (raw already exists).
CREATE SCHEMA IF NOT EXISTS claude_catalog.raw    COMMENT 'Bronze/raw layer: data as received';
CREATE SCHEMA IF NOT EXISTS claude_catalog.silver COMMENT 'Silver layer: cleaned, validated, SCD-managed';
CREATE SCHEMA IF NOT EXISTS claude_catalog.gold   COMMENT 'Gold layer: star schema and business aggregates';
CREATE VOLUME IF NOT EXISTS claude_catalog.raw.landing COMMENT 'Landing zone for source CSV files (one folder per batch)';
