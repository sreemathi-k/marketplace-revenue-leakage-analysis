/* =====================================================================
   04_analysis_queries.sql
   Run after 02_clean_layer.sql and 03_revenue_leakage_view.sql.
   Revenue order = delivered with a valid quantity (is_revenue_order = 1).
   Leakage = gross_revenue - net_revenue.
   ===================================================================== */
USE leakage_db;

/* ---------------------------------------------------------------------
   0. VALIDATION (run first, results must match)
   --------------------------------------------------------------------- */

-- V1: One row per order. Expect 22000 / 22000.
SELECT COUNT(*) rows_n, COUNT(DISTINCT order_id) uniq FROM revenue_leakage;

-- V2: View totals must equal source totals (proves no fan-out).
-- Expect discounts 5,732,831 and shipping 1,039,674 on both sides.
SELECT ROUND(SUM(discount_total),2) view_disc,
       (SELECT ROUND(SUM(discount_amount),2) FROM clean_discounts) src_disc,
       ROUND(SUM(shipping_total),2) view_ship,
       (SELECT ROUND(SUM(COALESCE(shipping_cost,0)),2) FROM clean_logistics) src_ship
FROM revenue_leakage;

-- V3: Headline. Expect 4273 orders, gross 12,599,415, net 10,765,473.50, leakage 14.6%.
SELECT SUM(is_revenue_order) revenue_orders,
       ROUND(SUM(CASE WHEN is_revenue_order THEN gross_revenue END),2) gross,
       ROUND(SUM(net_revenue),2) net,
       ROUND(100 * (1 - SUM(net_revenue) / SUM(CASE WHEN is_revenue_order THEN gross_revenue END)),1) leakage_pct
FROM revenue_leakage;

/* ---------------------------------------------------------------------
   1. WHERE DOES THE LEAKAGE COME FROM?
   --------------------------------------------------------------------- */

-- Q1: Leakage waterfall. Where does the gap between gross and net come from?
WITH w AS (
  SELECT SUM(gross_revenue) gross, SUM(discount_total) disc, SUM(refund_amount) refund,
         SUM(shipping_total) ship, SUM(reverse_shipping_total) rev_ship,
         SUM(payment_fee) fee, SUM(net_revenue) net
  FROM revenue_leakage
  WHERE is_revenue_order = 1            -- delivered orders with valid quantity only
)
SELECT 'Discounts' component, ROUND(disc,2) amount, ROUND(100*disc/gross,2) pct_of_gross FROM w
UNION ALL SELECT 'Refunds', ROUND(refund,2), ROUND(100*refund/gross,2) FROM w
UNION ALL SELECT 'Shipping', ROUND(ship,2), ROUND(100*ship/gross,2) FROM w
UNION ALL SELECT 'Reverse shipping', ROUND(rev_ship,2), ROUND(100*rev_ship/gross,2) FROM w
UNION ALL SELECT 'Payment fees', ROUND(fee,2), ROUND(100*fee/gross,2) FROM w
UNION ALL SELECT 'CHECK (must be 0)',   -- gross minus all components should equal net
       ROUND(gross - disc - refund - ship - rev_ship - fee - net,2), NULL FROM w;

-- Q2: Leakage by category, ranked. Which category loses the most?
SELECT category,
       COUNT(*) orders,
       ROUND(SUM(gross_revenue),2) gross,
       ROUND(SUM(gross_revenue - net_revenue),2) leakage,      -- gross minus net = leakage
       ROUND(100 * SUM(gross_revenue - net_revenue) / SUM(gross_revenue),1) leakage_pct,
       RANK() OVER (ORDER BY SUM(gross_revenue - net_revenue) DESC) leakage_rank
FROM revenue_leakage
WHERE is_revenue_order = 1
GROUP BY category
ORDER BY leakage_rank;

/* ---------------------------------------------------------------------
   2. WHEN DOES IT HAPPEN?
   --------------------------------------------------------------------- */

-- Q5: Monthly leakage and change vs previous month.
WITH m AS (
  SELECT order_month,
         ROUND(SUM(gross_revenue),2) gross,
         ROUND(SUM(gross_revenue - net_revenue),2) leakage
  FROM revenue_leakage
  WHERE is_revenue_order = 1
  GROUP BY order_month
)
SELECT order_month, gross, leakage,
       ROUND(100 * leakage / gross,1) leakage_pct,
       ROUND(100 * (leakage - LAG(leakage) OVER (ORDER BY order_month))
             / LAG(leakage) OVER (ORDER BY order_month),1) mom_change_pct   -- % change vs last month
FROM m
ORDER BY order_month;

-- Q8: Which leakage component drives the spike months (Feb, Oct, Dec)?
SELECT order_month,
       ROUND(100 * SUM(discount_total) / SUM(gross_revenue),1) disc_pct,
       ROUND(100 * SUM(refund_amount) / SUM(gross_revenue),1) refund_pct,
       ROUND(100 * SUM(shipping_total + reverse_shipping_total) / SUM(gross_revenue),1) logistics_pct,
       ROUND(100 * SUM(payment_fee) / SUM(gross_revenue),1) fee_pct
FROM revenue_leakage
WHERE is_revenue_order = 1
GROUP BY order_month
ORDER BY order_month;

-- Q10: Discount amount by month and type (delivered orders only).
SELECT r.order_month,
       SUM(CASE WHEN d.discount_type = 'FESTIVAL'  THEN d.discount_amount ELSE 0 END) festival,
       SUM(CASE WHEN d.discount_type = 'COUPON'    THEN d.discount_amount ELSE 0 END) coupon,
       SUM(CASE WHEN d.discount_type = 'BANKOFFER' THEN d.discount_amount ELSE 0 END) bank_offer,
       SUM(CASE WHEN d.discount_type = 'UNKNOWN'   THEN d.discount_amount ELSE 0 END) unknown_type
FROM clean_discounts d
JOIN revenue_leakage r ON r.order_id = d.order_id AND r.is_revenue_order = 1
GROUP BY r.order_month
ORDER BY r.order_month;

-- Q11: Refunds per month. More refunded orders, or bigger refunds? (explains Feb)
SELECT order_month,
       SUM(has_confirmed_return) refunded_orders,
       ROUND(SUM(refund_amount),2) refund_value,
       ROUND(AVG(CASE WHEN has_confirmed_return = 1 THEN refund_amount END),0) avg_refund
FROM revenue_leakage
WHERE is_revenue_order = 1
GROUP BY order_month
ORDER BY order_month;

/* ---------------------------------------------------------------------
   3. WHICH PRODUCTS?
   --------------------------------------------------------------------- */

-- Q4: Top 3 leaking products in each category.
WITH p AS (
  SELECT category, product_id,
         COUNT(*) orders,
         ROUND(SUM(gross_revenue - net_revenue),2) leakage
  FROM revenue_leakage
  WHERE is_revenue_order = 1
  GROUP BY category, product_id
), ranked AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY category ORDER BY leakage DESC) rn   -- rank inside each category
  FROM p
)
SELECT category, product_id, orders, leakage, rn
FROM ranked
WHERE rn <= 3
ORDER BY category, rn;

-- Q6: Pareto. How many products make up 80% of leakage? Expect 542 of 1647 (32.9%).
WITH p AS (
  SELECT product_id, SUM(gross_revenue - net_revenue) leakage
  FROM revenue_leakage
  WHERE is_revenue_order = 1
  GROUP BY product_id
), c AS (
  SELECT product_id, leakage,
         SUM(leakage) OVER (ORDER BY leakage DESC, product_id) running,   -- running total, biggest first
         SUM(leakage) OVER () total
  FROM p
)
SELECT COUNT(*) products_in_top80,
       (SELECT COUNT(*) FROM p) total_products,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM p),1) pct_of_products
FROM c
WHERE running - leakage < 0.8 * total;   -- keep rows until the running total crosses 80%

/* ---------------------------------------------------------------------
   4. DISCOUNTS
   --------------------------------------------------------------------- */

-- Q7: Discount amount by type and stackable flag (delivered orders only).
-- All rows must add up to 1,068,254 (ties to the waterfall).
SELECT d.discount_type, d.is_stackable,
       COUNT(*) discount_rows,
       ROUND(SUM(d.discount_amount),2) discount_amount
FROM clean_discounts d
JOIN revenue_leakage r ON r.order_id = d.order_id AND r.is_revenue_order = 1
GROUP BY d.discount_type, d.is_stackable
ORDER BY discount_amount DESC;

/* ---------------------------------------------------------------------
   5. LEAKAGE OUTSIDE THE CORE DEFINITION
   --------------------------------------------------------------------- */

-- Q3a: Logistics cost on orders that earned no revenue (cancelled, pending, etc.)
SELECT order_status, COUNT(*) orders,
       ROUND(SUM(shipping_total + reverse_shipping_total),2) logistics_cost
FROM revenue_leakage
WHERE is_revenue_order = 0
GROUP BY order_status
ORDER BY logistics_cost DESC;

-- Q3b: Refunds paid with no recorded return (anomaly, reported separately).
-- Expect 69 orders, 188,027.
SELECT COUNT(*) orders,
       ROUND(SUM(GREATEST(gross_revenue - discount_total,0)),2) refund_value   -- amount customer paid
FROM revenue_leakage
WHERE is_revenue_order = 1
  AND has_refund_without_return = 1
  AND has_confirmed_return = 0;         -- skip orders already counted as confirmed returns

-- Q13: Order value tied to LOST shipments, by order status (verification item, not a confirmed loss).
-- EXISTS counts each order once even if it has several shipment rows.
SELECT r.order_status, COUNT(*) orders, ROUND(SUM(r.gross_revenue),2) order_value
FROM revenue_leakage r
WHERE EXISTS (SELECT 1 FROM clean_logistics l
              WHERE l.order_id = r.order_id AND l.delivery_status = 'LOST')
GROUP BY r.order_status
ORDER BY order_value DESC;

/* ---------------------------------------------------------------------
   6. PAYMENT FEES
   --------------------------------------------------------------------- */

-- Q14: Payment fee cost by method (delivered orders). Which method costs the most?
SELECT payment_method, COUNT(*) orders,
       ROUND(SUM(gross_revenue),2) gross,
       ROUND(SUM(payment_fee),2) fee,
       ROUND(100 * SUM(payment_fee) / SUM(gross_revenue),2) fee_pct
FROM revenue_leakage
WHERE is_revenue_order = 1
GROUP BY payment_method
ORDER BY fee DESC;

/* ---------------------------------------------------------------------
   7. SENSITIVITY: DOES THE RESULT CHANGE IF SHIPPED ORDERS COUNT AS REVENUE?
   --------------------------------------------------------------------- */

-- Q12: First row must match the headline (4273 / 12,599,415 / 14.6%). Second row: 14.9%.
WITH x AS (
  SELECT order_status, gross_revenue,
         discount_total + shipping_total + reverse_shipping_total
           + ROUND(gross_revenue * fee_pct / 100, 2)                                  -- fee
           + IF(has_confirmed_return = 1, GREATEST(gross_revenue - discount_total, 0), 0) AS leakage   -- refund
  FROM revenue_leakage
  WHERE order_status IN ('DELIVERED','SHIPPED') AND quantity IS NOT NULL
)
SELECT 'DELIVERED only' scenario, COUNT(*) orders, ROUND(SUM(gross_revenue),2) gross,
       ROUND(SUM(leakage),2) leakage, ROUND(100 * SUM(leakage) / SUM(gross_revenue),1) leakage_pct
FROM x WHERE order_status = 'DELIVERED'
UNION ALL
SELECT 'DELIVERED + SHIPPED', COUNT(*), ROUND(SUM(gross_revenue),2), ROUND(SUM(leakage),2),
       ROUND(100 * SUM(leakage) / SUM(gross_revenue),1)
FROM x;