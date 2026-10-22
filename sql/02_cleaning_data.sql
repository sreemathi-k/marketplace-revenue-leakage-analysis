/* =====================================================================
   02_clean_layer.sql  (consolidated: ALL cleaning rules in one place)
   Run the WHOLE script (lightning bolt), not one statement at a time.
   Safe to re-run: every table is dropped and rebuilt.
   Rules: bad numbers -> NULL | blank/unknown text -> 'UNKNOWN'
          every issue is logged in dq_quarantine with its raw value
   ===================================================================== */
USE leakage_db;

/* ---------- 1. PAYMENT FEES ---------- */
DROP TABLE IF EXISTS clean_payment_fees;
CREATE TABLE clean_payment_fees AS
SELECT UPPER(TRIM(payment_method)) AS payment_method,
       CAST(fee_percentage AS DECIMAL(5,2)) AS fee_pct,
       CASE WHEN TRIM(settlement_days) REGEXP '^[0-9]+$'
            THEN CAST(settlement_days AS UNSIGNED) END AS settlement_days
FROM raw_payment_fees;
ALTER TABLE clean_payment_fees ADD PRIMARY KEY (payment_method);

-- UNKNOWN method gets the simple average of the known fees
INSERT INTO clean_payment_fees
SELECT 'UNKNOWN', ROUND(AVG(fee_pct),2), NULL FROM clean_payment_fees;

/* ---------- 2. PRODUCTS ---------- */

DROP TABLE IF EXISTS clean_products;
CREATE TABLE clean_products AS
SELECT CAST(product_id AS UNSIGNED) AS product_id,
       COALESCE(NULLIF(TRIM(category),''),'UNKNOWN')     AS category,       -- blank -> UNKNOWN
       COALESCE(NULLIF(TRIM(sub_category),''),'UNKNOWN') AS sub_category,
       COALESCE(NULLIF(TRIM(brand),''),'UNKNOWN')        AS brand,
       CASE WHEN supplier_id REGEXP '^[0-9]+$' THEN CAST(supplier_id AS UNSIGNED) END AS supplier_id,
       CASE WHEN cost_price REGEXP '^[0-9]+(\\.[0-9]+)?$'
            THEN CAST(cost_price AS DECIMAL(10,2)) END AS cost_price,       -- bad -> NULL
       CAST(mrp AS DECIMAL(10,2)) AS mrp,
       CASE WHEN weight_kg REGEXP '^[0-9]+(\\.[0-9]+)?$'
            THEN CAST(weight_kg AS DECIMAL(6,2)) END AS weight_kg,
       STR_TO_DATE(launch_date,'%Y-%m-%d') AS launch_date
FROM raw_products;
ALTER TABLE clean_products ADD PRIMARY KEY (product_id);

/* ---------- 3. ORDERS ---------- */
DROP TABLE IF EXISTS clean_orders;
CREATE TABLE clean_orders AS
SELECT CAST(order_id AS UNSIGNED) AS order_id,
       STR_TO_DATE(order_date,'%Y-%m-%d') AS order_date,
       CASE WHEN customer_id REGEXP '^[0-9]+$' THEN CAST(customer_id AS UNSIGNED) END AS customer_id,
       CAST(product_id AS UNSIGNED) AS product_id,
       CASE WHEN quantity REGEXP '^[1-9][0-9]*$'
            THEN CAST(quantity AS UNSIGNED) END AS quantity,                 -- bad -> NULL
       CAST(selling_price AS DECIMAL(10,2)) AS selling_price,
       -- known values kept, everything else (blank, odd) -> UNKNOWN
       CASE WHEN UPPER(TRIM(order_status)) IN ('DELIVERED','CANCELLED','PENDING','SHIPPED')
            THEN UPPER(TRIM(order_status)) ELSE 'UNKNOWN' END AS order_status,
       CASE WHEN UPPER(TRIM(payment_method)) IN ('UPI','CARD','COD','WALLET','NETBANKING','PAYLATER')
            THEN UPPER(TRIM(payment_method)) ELSE 'UNKNOWN' END AS payment_method,   -- INVALID -> UNKNOWN
       CASE WHEN UPPER(TRIM(order_channel)) IN ('APP','WEB','CALL_CENTER')
            THEN UPPER(TRIM(order_channel)) ELSE 'UNKNOWN' END AS order_channel,
       CASE WHEN warehouse_id REGEXP '^[0-9]+$' THEN CAST(warehouse_id AS UNSIGNED) END AS warehouse_id
FROM raw_orders;
ALTER TABLE clean_orders ADD PRIMARY KEY (order_id);
select distinct order_channel from raw_orders;

/* ---------- 4. DISCOUNTS ---------- */
DROP TABLE IF EXISTS clean_discounts;
CREATE TABLE clean_discounts AS
SELECT CAST(discount_id AS UNSIGNED) AS discount_id,
       CAST(order_id AS UNSIGNED) AS order_id,
       CAST(discount_amount AS DECIMAL(10,2)) AS discount_amount,
       CASE WHEN UPPER(TRIM(discount_type)) IN ('BANKOFFER','COUPON','FESTIVAL')
            THEN UPPER(TRIM(discount_type)) ELSE 'UNKNOWN' END AS discount_type,     -- blank -> UNKNOWN
       UPPER(TRIM(coupon_code)) AS coupon_code,
       CASE WHEN UPPER(TRIM(is_stackable)) IN ('Y','N')
            THEN UPPER(TRIM(is_stackable)) ELSE 'UNKNOWN' END AS is_stackable
FROM raw_discounts;
ALTER TABLE clean_discounts ADD PRIMARY KEY (discount_id);

/* ---------- 5. LOGISTICS ---------- */
DROP TABLE IF EXISTS clean_logistics;
CREATE TABLE clean_logistics AS
SELECT CAST(logistics_id AS UNSIGNED) AS logistics_id,
       CAST(order_id AS UNSIGNED) AS order_id,
       CASE WHEN shipping_cost REGEXP '^[0-9]+(\\.[0-9]+)?$'
            THEN CAST(shipping_cost AS DECIMAL(10,2)) END AS shipping_cost,         -- bad -> NULL
       CASE WHEN reverse_shipping_cost REGEXP '^[0-9]+(\\.[0-9]+)?$'
            THEN CAST(reverse_shipping_cost AS DECIMAL(10,2)) END AS reverse_shipping_cost,
       CASE WHEN delivery_days REGEXP '^[0-9]+$' THEN CAST(delivery_days AS UNSIGNED) END AS delivery_days,
       CASE WHEN UPPER(TRIM(delivery_status)) IN ('LOST','ON_TIME','DELAYED')
            THEN UPPER(TRIM(delivery_status)) ELSE 'UNKNOWN' END AS delivery_status
FROM raw_logistics;
ALTER TABLE clean_logistics ADD PRIMARY KEY (logistics_id);

/* ---------- 6. RETURNS ---------- */
DROP TABLE IF EXISTS clean_returns;
CREATE TABLE clean_returns AS
SELECT CAST(return_id AS UNSIGNED) AS return_id,
       CAST(order_id AS UNSIGNED) AS order_id,
       CASE WHEN UPPER(TRIM(return_flag)) IN ('Y','N')
            THEN UPPER(TRIM(return_flag)) ELSE 'UNKNOWN' END AS return_flag,        -- X -> UNKNOWN
       CASE WHEN TRIM(return_reason) IN ('Customer Changed Mind','Late Delivery','Wrong Item','Quality Issue','Damaged')
            THEN TRIM(return_reason) ELSE 'UNKNOWN' END AS return_reason,
       STR_TO_DATE(return_initiated_date,'%Y-%m-%d') AS return_initiated_date,
       CASE WHEN UPPER(TRIM(refund_mode)) IN ('ORIGINAL PAYMENT','WALLET','UPI')
            THEN UPPER(TRIM(refund_mode)) ELSE 'UNKNOWN' END AS refund_mode,
       CASE WHEN UPPER(TRIM(refund_status)) IN ('PROCESSED','REJECTED','PENDING')
            THEN UPPER(TRIM(refund_status)) ELSE 'UNKNOWN' END AS refund_status,
       CASE WHEN UPPER(TRIM(customer_fault_flag)) IN ('Y','N')
            THEN UPPER(TRIM(customer_fault_flag)) ELSE 'UNKNOWN' END AS customer_fault_flag
FROM raw_returns;
ALTER TABLE clean_returns ADD PRIMARY KEY (return_id);

/* ---------- 7. QUARANTINE LOG (rebuilt each run, so no duplicates) ---------- */
DROP TABLE IF EXISTS dq_quarantine;
CREATE TABLE dq_quarantine (
  dq_id INT AUTO_INCREMENT PRIMARY KEY,
  source_table VARCHAR(30), record_id VARCHAR(50), column_name VARCHAR(40),
  raw_value VARCHAR(50), issue VARCHAR(60),
  logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Logged from RAW, using the same rules as above (bad number or value not in the known list)
INSERT INTO dq_quarantine (source_table, record_id, column_name, raw_value, issue)
-- orders
SELECT 'orders', order_id, 'quantity', quantity, 'invalid number'
  FROM raw_orders WHERE quantity IS NULL OR quantity NOT REGEXP '^[1-9][0-9]*$'
UNION ALL SELECT 'orders', order_id, 'order_status', order_status, 'blank/invalid value'
  FROM raw_orders WHERE COALESCE(UPPER(TRIM(order_status)),'') NOT IN ('DELIVERED','CANCELLED','PENDING','SHIPPED')
UNION ALL SELECT 'orders', order_id, 'payment_method', payment_method, 'blank/invalid value'
  FROM raw_orders WHERE COALESCE(UPPER(TRIM(payment_method)),'') NOT IN ('UPI','CARD','COD','WALLET','NETBANKING','PAYLATER')
UNION ALL SELECT 'orders', order_id, 'order_channel', order_channel, 'blank/invalid value'
  FROM raw_orders WHERE COALESCE(UPPER(TRIM(order_channel)),'') NOT IN ('APP','WEB','CALL_CENTER')
-- products
UNION ALL SELECT 'products', product_id, 'cost_price', cost_price, 'invalid number'
  FROM raw_products WHERE cost_price IS NULL OR cost_price NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'products', product_id, 'category', category, 'blank value'
  FROM raw_products WHERE COALESCE(TRIM(category),'') = ''
UNION ALL SELECT 'products', product_id, 'sub_category', sub_category, 'blank value'
  FROM raw_products WHERE COALESCE(TRIM(sub_category),'') = ''
UNION ALL SELECT 'products', product_id, 'brand', brand, 'blank value'
  FROM raw_products WHERE COALESCE(TRIM(brand),'') = ''
-- discounts
UNION ALL SELECT 'discounts', discount_id, 'discount_type', discount_type, 'blank/invalid value'
  FROM raw_discounts WHERE COALESCE(UPPER(TRIM(discount_type)),'') NOT IN ('BANKOFFER','COUPON','FESTIVAL')
UNION ALL SELECT 'discounts', discount_id, 'is_stackable', is_stackable, 'blank/invalid value'
  FROM raw_discounts WHERE COALESCE(UPPER(TRIM(is_stackable)),'') NOT IN ('Y','N')
-- logistics
UNION ALL SELECT 'logistics', logistics_id, 'shipping_cost', shipping_cost, 'invalid number'
  FROM raw_logistics WHERE shipping_cost IS NULL OR shipping_cost NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL SELECT 'logistics', logistics_id, 'delivery_status', delivery_status, 'blank/invalid value'
  FROM raw_logistics WHERE COALESCE(UPPER(TRIM(delivery_status)),'') NOT IN ('LOST','ON_TIME','DELAYED')
-- returns
UNION ALL SELECT 'returns', return_id, 'return_flag', return_flag, 'blank/invalid value'
  FROM raw_returns WHERE COALESCE(UPPER(TRIM(return_flag)),'') NOT IN ('Y','N')
UNION ALL SELECT 'returns', return_id, 'refund_status', refund_status, 'blank/invalid value'
  FROM raw_returns WHERE COALESCE(UPPER(TRIM(refund_status)),'') NOT IN ('PROCESSED','REJECTED','PENDING')
UNION ALL SELECT 'returns', return_id, 'refund_mode', refund_mode, 'blank/invalid value'
  FROM raw_returns WHERE COALESCE(UPPER(TRIM(refund_mode)),'') NOT IN ('ORIGINAL PAYMENT','WALLET','UPI')
UNION ALL SELECT 'returns', return_id, 'return_reason', return_reason, 'blank/invalid value'
  FROM raw_returns WHERE COALESCE(TRIM(return_reason),'') NOT IN ('Customer Changed Mind','Late Delivery','Wrong Item','Quality Issue','Damaged')
UNION ALL SELECT 'returns', r.return_id, 'order_status', o.order_status, 'return on cancelled/pending order'
  FROM raw_returns r JOIN raw_orders o ON o.order_id = r.order_id
  WHERE UPPER(TRIM(o.order_status)) IN ('CANCELLED','PENDING');

/* ---------- 8. CHECKS (run after the script) ---------- */
-- Raw vs clean row counts (payment_fees clean = raw + 1 UNKNOWN row)
SELECT 'orders' t, (SELECT COUNT(*) FROM raw_orders) raw_n, (SELECT COUNT(*) FROM clean_orders) clean_n
UNION ALL SELECT 'products',     (SELECT COUNT(*) FROM raw_products),     (SELECT COUNT(*) FROM clean_products)
UNION ALL SELECT 'discounts',    (SELECT COUNT(*) FROM raw_discounts),    (SELECT COUNT(*) FROM clean_discounts)
UNION ALL SELECT 'logistics',    (SELECT COUNT(*) FROM raw_logistics),    (SELECT COUNT(*) FROM clean_logistics)
UNION ALL SELECT 'returns',      (SELECT COUNT(*) FROM raw_returns),      (SELECT COUNT(*) FROM clean_returns)
UNION ALL SELECT 'payment_fees', (SELECT COUNT(*) FROM raw_payment_fees), (SELECT COUNT(*) FROM clean_payment_fees);

-- Issues logged per column
SELECT source_table, column_name, issue, COUNT(*) n
FROM dq_quarantine GROUP BY 1,2,3 ORDER BY 1,2;
SELECT category, COUNT(*) FROM clean_products GROUP BY 1 ORDER BY 1;

select * from clean_payment_fees;