-- =====================================================================
-- Marketplace Revenue Leakage & Gap Analysis  |  MySQL 8.0
-- Step 1: create database and raw tables
-- Rule: never delete from raw tables. Clean tables are built from raw.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS leakage_db;
USE leakage_db;

DROP TABLE IF EXISTS raw_payment_fees, raw_logistics, raw_discounts,
                     raw_orders, raw_products, raw_returns;

CREATE TABLE raw_payment_fees (
  payment_method  VARCHAR(50),
  fee_percentage  VARCHAR(50),
  settlement_days VARCHAR(50),
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE raw_logistics (
  logistics_id VARCHAR(50), 
  order_id VARCHAR(50),
  shipping_cost VARCHAR(50),
  reverse_shipping_cost VARCHAR(50),
  delivery_days VARCHAR(50),
  delivery_status VARCHAR(50),
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE raw_discounts (
  discount_id VARCHAR(50),
  order_id VARCHAR(50),
  discount_amount VARCHAR(50),
  discount_type VARCHAR(50),
  coupon_code VARCHAR(50), 
  is_stackable VARCHAR(50),
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE raw_orders (
  order_id VARCHAR(50),
  order_date VARCHAR(50),
  customer_id VARCHAR(50),
  product_id VARCHAR(50), 
  quantity VARCHAR(50),
  selling_price VARCHAR(50),
  order_status VARCHAR(50),
  payment_method VARCHAR(50),
  order_channel VARCHAR(50),
  warehouse_id VARCHAR(50),
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE raw_products (
  product_id VARCHAR(50), 
  category VARCHAR(50),
  sub_category VARCHAR(50),
  brand VARCHAR(50),
  supplier_id VARCHAR(50),
  cost_price VARCHAR(50),
  mrp VARCHAR(50),
  weight_kg VARCHAR(50), 
  launch_date VARCHAR(50),
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE raw_returns (
  return_id VARCHAR(50),
  order_id VARCHAR(50),
  return_flag VARCHAR(50),
  return_reason VARCHAR(50),
  return_initiated_date VARCHAR(50),
  refund_mode VARCHAR(50),
  refund_status VARCHAR(50),
  customer_fault_flag VARCHAR(50),
  loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- step 3
select count(*) from raw_discounts; -- 9000
select count(*) from raw_logistics; -- 13000
select count(*) from raw_orders; -- 22000
select count(*) from raw_payment_fees; -- 6
select count(*) from raw_returns; -- 4000
select count(*) from raw_products; -- 1800

-- GRAIN CHECK
SELECT 'orders' t, COUNT(*) total, COUNT(DISTINCT order_id) uniq FROM raw_orders
UNION ALL SELECT 'discounts', COUNT(*), COUNT(DISTINCT order_id) FROM raw_discounts
UNION ALL SELECT 'returns', COUNT(*), COUNT(DISTINCT order_id) FROM raw_returns
UNION ALL SELECT 'logistics', COUNT(*), COUNT(DISTINCT order_id) FROM raw_logistics;

-- ORPHAN  check 
SELECT 'logistics' t, COUNT(*) orphans FROM raw_logistics l
  LEFT JOIN raw_orders o ON o.order_id = l.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'discounts', COUNT(*) FROM raw_discounts d
  LEFT JOIN raw_orders o ON o.order_id = d.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'returns', COUNT(*) FROM raw_returns r
  LEFT JOIN raw_orders o ON o.order_id = r.order_id WHERE o.order_id IS NULL;

-- Distinct-values scan
  
SELECT order_status, COUNT(*) FROM raw_orders GROUP BY order_status;
SELECT payment_method, COUNT(*) FROM raw_orders GROUP BY payment_method;
SELECT return_flag, COUNT(*) FROM raw_returns GROUP BY return_flag;
SELECT is_stackable, COUNT(*) FROM raw_discounts GROUP BY is_stackable;
SELECT * FROM raw_payment_fees;

-- A. Are IDs duplicated, or are these genuine multi-row cases?
SELECT 'discount_id' k, COUNT(*) total, COUNT(DISTINCT discount_id) uniq FROM raw_discounts
UNION ALL SELECT 'return_id', COUNT(*), COUNT(DISTINCT return_id) FROM raw_returns
UNION ALL SELECT 'logistics_id', COUNT(*), COUNT(DISTINCT logistics_id) FROM raw_logistics;

-- B. Is blank status '' or NULL? Same check for other blanks
SELECT SUM(order_status = '') AS blank_status, SUM(order_status IS NULL) AS null_status FROM raw_orders;

-- C. Logic checks across tables
SELECT o.order_status, COUNT(DISTINCT l.order_id) orders_with_logistics
FROM raw_orders o JOIN raw_logistics l ON l.order_id = o.order_id
GROUP BY o.order_status;

SELECT o.order_status, COUNT(DISTINCT r.order_id) orders_with_returns
FROM raw_orders o JOIN raw_returns r ON r.order_id = o.order_id
GROUP BY o.order_status;

-- D. Return rows by flag and refund status
SELECT return_flag, refund_status, COUNT(*) FROM raw_returns GROUP BY 1, 2;


-- Bad (blank / non-numeric / invalid) values per column


SELECT 'orders.quantity' col, COUNT(*) bad FROM raw_orders
  WHERE quantity IS NULL OR quantity NOT REGEXP '^[1-9][0-9]*$'
UNION ALL SELECT 'orders.selling_price', COUNT(*) FROM raw_orders
  WHERE selling_price IS NULL OR selling_price NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'orders.order_date', COUNT(*) FROM raw_orders
  WHERE STR_TO_DATE(order_date,'%Y-%m-%d') IS NULL
UNION ALL SELECT 'products.cost_price', COUNT(*) FROM raw_products
  WHERE cost_price IS NULL OR cost_price NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'products.mrp', COUNT(*) FROM raw_products
  WHERE mrp IS NULL OR mrp NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'discounts.discount_amount', COUNT(*) FROM raw_discounts
  WHERE discount_amount IS NULL OR discount_amount NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'logistics.shipping_cost', COUNT(*) FROM raw_logistics
  WHERE shipping_cost IS NULL OR shipping_cost NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'logistics.reverse_shipping_cost', COUNT(*) FROM raw_logistics
  WHERE reverse_shipping_cost IS NULL OR reverse_shipping_cost NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'returns.return_initiated_date', COUNT(*) FROM raw_returns
  WHERE STR_TO_DATE(return_initiated_date,'%Y-%m-%d') IS NULL;

-- Products: key uniqueness, and orders pointing to missing products
SELECT COUNT(*) total, COUNT(DISTINCT product_id) uniq FROM raw_products;
SELECT COUNT(*) AS orders_without_product FROM raw_orders o
  LEFT JOIN raw_products p ON p.product_id = o.product_id WHERE p.product_id IS NULL;

-- Date range of orders
SELECT MIN(order_date), MAX(order_date) FROM raw_orders;

select * from raw_products;
select distinct discount_type from raw_discounts;