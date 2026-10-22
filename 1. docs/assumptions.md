# Assumptions and Business Rules

Every rule below was applied in the clean layer or the `revenue_leakage` view. Amounts are in the dataset's currency units.

## Revenue definitions

1. `selling_price` is the pre-discount unit price. `discount_amount` is a per-order total.
2. **Revenue order** = `order_status = 'DELIVERED'` and a valid quantity. Cancelled, pending, shipped and unknown-status orders do not count as revenue.
3. Gross revenue = quantity × selling_price.
4. Net revenue = gross − discounts − refund − shipping − reverse shipping − payment fee.
5. Leakage = gross − net.

## Returns and refunds

6. The returns table has no refund amount. Refund = what the customer paid (gross − discounts, floored at 0), assuming a full refund. Partial refunds cannot be measured.
7. A refund is counted once per order, even when an order has several return rows (4,000 return rows cover 3,656 orders).
8. Return tiers:
   - **Confirmed:** `return_flag = Y` and `refund_status = PROCESSED`. Counted as refund leakage on revenue orders.
   - **Exposure:** `Y` and `PENDING`. Not counted as leakage yet.
   - **No leakage:** `REJECTED`.
   - **Anomaly (reported separately):** `N` and `PROCESSED` (refund paid with no recorded return), `X` flags, blank refund status, and returns on cancelled or pending orders.
9. Returns on cancelled or pending orders (1,580 rows) are treated as data-integrity exceptions and excluded from confirmed return leakage.

## Costs

10. Shipping and reverse shipping costs are summed per order (an order can have several shipment rows).
11. Missing (invalid) shipping costs are NULL in the clean table, treated as 0 in sums, and flagged with `shipping_missing_flag`. Shipping leakage is therefore understated by an unknown amount.
12. Payment fee = gross × fee percentage, for revenue orders only.
13. Orders with an invalid payment method are labeled `UNKNOWN` and use the simple average of the six known fee rates (2.20%). The true fee is unknown, so this is an estimate.
14. Logistics cost on non-revenue orders (for example, cancelled orders) is reported as a separate bucket, not deleted.

## Data cleaning

15. Raw tables are loaded as `VARCHAR` with no constraints, so no value is rejected or silently converted to 0.
16. Invalid numeric values (quantity, cost price, shipping cost) become NULL in the clean layer. Invalid quantity excludes the order from revenue totals. Invalid cost price excludes the product from margin analysis only, because leakage does not use cost.
17. Blank or invalid text values become `UNKNOWN`: order status, payment method, return flag, refund status, category, sub-category, brand, discount type, stackable flag, order channel, refund mode, return reason, delivery status.
18. Every issue is logged in `dq_quarantine` (table, record id, column, original value, issue). Nothing is dropped.
19. Duplicate IDs: none found (`discount_id`, `return_id`, `logistics_id`, `order_id`, `product_id` are all unique). Extra rows per order are genuine multiple events and are summed or flagged, not removed.

## Not used in leakage math

20. Delivery status (`LOST`, `DELAYED`, `ON_TIME`) is not used in leakage calculations because it contradicts order status in places. It is reported as a verification item.
21. `cost_price` and margin are not part of the leakage definition.

## Scenario assumptions (recommendations)

22. "Other-months discount rate" = about 7.8% of gross (the average of the ten months excluding Oct and Dec).
23. Recovery percentages (10%, 25%, 50%) are scenario assumptions, not forecasts.
