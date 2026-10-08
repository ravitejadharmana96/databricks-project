-- Raw layer: full snapshot of the chosen batch folder (job parameter :batch, e.g. batch_1 / batch_2).
-- Drops children first, then recreates parents -> children.

DROP TABLE IF EXISTS claude_catalog.raw.orders;
DROP TABLE IF EXISTS claude_catalog.raw.customers;
DROP TABLE IF EXISTS claude_catalog.raw.stores;
DROP TABLE IF EXISTS claude_catalog.raw.departments;

CREATE TABLE claude_catalog.raw.departments (
  department_id   INT           NOT NULL,
  department_name STRING,
  category        STRING,
  manager_name    STRING,
  annual_budget   DECIMAL(14,2),
  CONSTRAINT pk_departments PRIMARY KEY (department_id)
) COMMENT 'Raw layer: departments';

CREATE TABLE claude_catalog.raw.stores (
  store_id            INT NOT NULL,
  store_name          STRING,
  city                STRING,
  state               STRING,
  region              STRING,
  manager_name        STRING,
  square_feet         INT,
  open_date           DATE,
  source_updated_date DATE,
  CONSTRAINT pk_stores PRIMARY KEY (store_id)
) COMMENT 'Raw layer: stores';

CREATE TABLE claude_catalog.raw.customers (
  customer_id         INT NOT NULL,
  first_name          STRING,
  last_name           STRING,
  email               STRING,
  phone               STRING,
  city                STRING,
  state               STRING,
  segment             STRING,
  signup_date         DATE,
  preferred_store_id  INT,
  source_updated_date DATE,
  CONSTRAINT pk_customers PRIMARY KEY (customer_id),
  CONSTRAINT fk_customers_store FOREIGN KEY (preferred_store_id) REFERENCES claude_catalog.raw.stores (store_id)
) COMMENT 'Raw layer: customers';

CREATE TABLE claude_catalog.raw.orders (
  order_id       INT NOT NULL,
  customer_id    INT,
  store_id       INT,
  department_id  INT,
  order_date     DATE,
  status         STRING,
  quantity       INT,
  unit_price     DECIMAL(10,2),
  total_amount   DECIMAL(12,2),
  payment_method STRING,
  CONSTRAINT pk_orders PRIMARY KEY (order_id),
  CONSTRAINT fk_orders_customer   FOREIGN KEY (customer_id)   REFERENCES claude_catalog.raw.customers (customer_id),
  CONSTRAINT fk_orders_store      FOREIGN KEY (store_id)      REFERENCES claude_catalog.raw.stores (store_id),
  CONSTRAINT fk_orders_department FOREIGN KEY (department_id) REFERENCES claude_catalog.raw.departments (department_id)
) COMMENT 'Raw layer: orders';

INSERT INTO claude_catalog.raw.departments
SELECT CAST(department_id AS INT), department_name, category, manager_name, CAST(annual_budget AS DECIMAL(14,2))
FROM read_files(concat('/Volumes/claude_catalog/raw/landing/', :batch, '/departments.csv'), format => 'csv', header => true);

INSERT INTO claude_catalog.raw.stores
SELECT CAST(store_id AS INT), store_name, city, state, region, manager_name,
       CAST(square_feet AS INT), CAST(open_date AS DATE), CAST(source_updated_date AS DATE)
FROM read_files(concat('/Volumes/claude_catalog/raw/landing/', :batch, '/stores.csv'), format => 'csv', header => true);

INSERT INTO claude_catalog.raw.customers
SELECT CAST(customer_id AS INT), first_name, last_name, email, phone, city, state, segment,
       CAST(signup_date AS DATE), CAST(preferred_store_id AS INT), CAST(source_updated_date AS DATE)
FROM read_files(concat('/Volumes/claude_catalog/raw/landing/', :batch, '/customers.csv'), format => 'csv', header => true);

INSERT INTO claude_catalog.raw.orders
SELECT CAST(order_id AS INT), CAST(customer_id AS INT), CAST(store_id AS INT), CAST(department_id AS INT),
       CAST(order_date AS DATE), status, CAST(quantity AS INT), CAST(unit_price AS DECIMAL(10,2)),
       CAST(total_amount AS DECIMAL(12,2)), payment_method
FROM read_files(concat('/Volumes/claude_catalog/raw/landing/', :batch, '/orders.csv'), format => 'csv', header => true);
