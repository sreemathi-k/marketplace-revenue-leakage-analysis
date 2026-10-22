/* =====================================================================
   05_profit_analyis.sql
   Run after 02_clean_layer.sql and 03_revenue_leakage_view.sql
   Revenue order = delivered with a valid quantity (is_revenue_order = 1).
   ===================================================================== */
USE leakage_db;

-- P1: How many delivered orders have no cost price (excluded from profit)?
SELECT COUNT(*) AS orders_without_cost
FROM revenue_leakage r
LEFT JOIN clean_products p ON p.product_id = r.product_id
WHERE r.is_revenue_order = 1 AND p.cost_price IS NULL;

-- P2: Profit and margin, before and after leakage (delivered orders with a known cost)
SELECT COUNT(*) AS orders,
       ROUND(SUM(r.gross_revenue),2)                                    AS gross,
       ROUND(SUM(r.quantity * p.cost_price),2)                          AS cogs,        -- cost of goods sold
       ROUND(SUM(r.gross_revenue - r.quantity * p.cost_price),2)        AS profit_before_leakage,
       ROUND(SUM(r.net_revenue - r.quantity * p.cost_price),2)          AS profit_after_leakage,
       ROUND(100 * SUM(r.gross_revenue - r.quantity * p.cost_price) / NULLIF(SUM(r.gross_revenue),0),1) AS margin_before_pct,
       ROUND(100 * SUM(r.net_revenue - r.quantity * p.cost_price) /NULLIF(SUM(r.gross_revenue),0),1)   AS margin_after_pct
FROM revenue_leakage r
JOIN clean_products p ON p.product_id = r.product_id
WHERE r.is_revenue_order = 1 AND p.cost_price IS NOT NULL;

-- P3: Orders sold below cost (negative margin before any leakage)
SELECT COUNT(*) AS orders_sold_below_cost,
       ROUND(SUM(r.gross_revenue - r.quantity * p.cost_price),2) AS total_loss
FROM revenue_leakage r
JOIN clean_products p ON p.product_id = r.product_id
WHERE r.is_revenue_order = 1
  AND p.cost_price IS NOT NULL
  AND r.selling_price < p.cost_price;      -- price below unit cost
  
-- which category show high variation in profit margin across orders compared to others?
-- P4: Identify categories with high variation in order-level margins

WITH category_order_margin AS (
    SELECT
        r.category,
        r.order_id,
        (
            r.net_revenue - p.cost_price * r.quantity
        ) / NULLIF(r.gross_revenue, 0) AS profit_margin
    FROM revenue_leakage r
    JOIN clean_products p
        ON p.product_id = r.product_id
    WHERE r.is_revenue_order = 1
      AND p.cost_price IS NOT NULL
      AND r.gross_revenue > 0
)
SELECT
    category,
    COUNT(*) AS order_count,
    ROUND(AVG(profit_margin) * 100, 2) AS avg_margin_pct,
    ROUND(STDDEV(profit_margin) * 100, 2) AS margin_stddev_pct,
    SUM(
        CASE WHEN profit_margin < -1 THEN 1 ELSE 0 END
    ) AS orders_below_minus_100_pct
FROM category_order_margin
GROUP BY category
ORDER BY margin_stddev_pct DESC;