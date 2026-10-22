/* =====================================================================
   VIEW: revenue_leakage
   GRAIN: exactly one row per order (22,000 rows, matches clean_orders)
   PURPOSE: single trusted source for all leakage analysis.
            Each child table (discounts, logistics, returns) is collapsed
            to one row per order BEFORE joining, so revenue is never
            multiplied by one-to-many joins (fan-out).
   KEY RULES (see docs/assumptions.md):
     - selling_price is the pre-discount unit price
     - discount_amount is a per-order total
     - revenue order = DELIVERED with a valid quantity
     - refund = amount the customer paid (gross - discounts), once per order
     - net = gross - discounts - refund - shipping - reverse shipping - fee
   ===================================================================== */
CREATE OR REPLACE VIEW revenue_leakage AS

-- Aggregate discounts to order level to prevent join fan-out.
WITH d AS (
  SELECT order_id,
         SUM(discount_amount) AS discount_total,
         COUNT(*)             AS discount_rows
  FROM clean_discounts
  GROUP BY order_id
),

-- Aggregate forward and reverse logistics costs per order.
-- Missing costs are treated as zero but flagged for investigation.
l AS (
  SELECT order_id,
         SUM(COALESCE(shipping_cost,0))         AS shipping_total,
         SUM(COALESCE(reverse_shipping_cost,0)) AS reverse_shipping_total,
         MAX(shipping_cost IS NULL)             AS shipping_missing_flag
  FROM clean_logistics
  GROUP BY order_id
),

-- Create order-level return flags to prevent duplicate refunds.
-- Only processed refunds on confirmed returns count as core leakage.
r AS (
  SELECT order_id,
         MAX(return_flag = 'Y' AND refund_status = 'PROCESSED') AS has_confirmed_return,
         MAX(return_flag = 'Y' AND refund_status = 'PENDING')   AS has_pending_return,
         MAX(return_flag = 'N' AND refund_status = 'PROCESSED') AS has_refund_without_return
  FROM clean_returns
  GROUP BY order_id
),

-- Combine orders with product details, aggregated costs,
-- return flags, and payment fees while preserving all orders.
base AS (
  SELECT o.order_id, o.order_date, DATE_FORMAT(o.order_date,'%Y-%m') AS order_month,
         o.customer_id, o.product_id, p.category, p.sub_category, p.brand,
         o.order_status, o.payment_method, o.order_channel, o.warehouse_id,
         o.quantity, o.selling_price,
         o.quantity * o.selling_price            AS gross_revenue,   -- NULL if quantity invalid
         COALESCE(d.discount_total,0)            AS discount_total,
         COALESCE(l.shipping_total,0)            AS shipping_total,
         COALESCE(l.reverse_shipping_total,0)    AS reverse_shipping_total,
         COALESCE(l.shipping_missing_flag,0)     AS shipping_missing_flag,
         COALESCE(r.has_confirmed_return,0)      AS has_confirmed_return,
         COALESCE(r.has_pending_return,0)        AS has_pending_return,
         COALESCE(r.has_refund_without_return,0) AS has_refund_without_return,
         f.fee_pct,
         (o.order_status = 'DELIVERED' AND o.quantity IS NOT NULL) AS is_revenue_order
  FROM clean_orders o
  LEFT JOIN clean_products     p ON p.product_id     = o.product_id
  LEFT JOIN d                    ON d.order_id       = o.order_id
  LEFT JOIN l                    ON l.order_id       = o.order_id
  LEFT JOIN r                    ON r.order_id       = o.order_id
  LEFT JOIN clean_payment_fees f ON f.payment_method = o.payment_method
)

-- Calculate order-level fees, confirmed refunds, and net revenue.
-- Non-revenue orders retain zero net revenue but keep cost fields
-- available for separate operational leakage analysis.

SELECT base.*,
  IF(is_revenue_order, ROUND(gross_revenue * fee_pct / 100, 2), 0) AS payment_fee,
  IF(is_revenue_order AND has_confirmed_return = 1,
     GREATEST(gross_revenue - discount_total, 0), 0)               AS refund_amount,
  IF(is_revenue_order,
     gross_revenue - discount_total
       - IF(has_confirmed_return = 1, GREATEST(gross_revenue - discount_total, 0), 0)
       - shipping_total - reverse_shipping_total
       - ROUND(gross_revenue * fee_pct / 100, 2), 0)               AS net_revenue
FROM base;
