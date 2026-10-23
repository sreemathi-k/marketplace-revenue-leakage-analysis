# Findings

All figures are for revenue orders (delivered, valid quantity: 4,273 orders) unless stated. Gross revenue = 12,599,415. Amounts are in the dataset's currency units.

## 1. Headline

| Metric | Value |
|---|---|
| Revenue orders | 4,273 |
| Gross revenue | 12,599,415.00 |
| Net revenue | 10,765,473.50 |
| Leakage | 1,833,941.50 (14.6%) |

Validation: the view has 22,000 rows (22,000 distinct orders); discount total 5,732,831 and shipping total 1,039,674 match the source tables exactly; the waterfall check (gross − components − net) is 0.

## 2. Leakage waterfall

| Component | Amount | % of gross | Share of leakage |
|---|---|---|---|
| Discounts | 1,068,254.00 | 8.48% | 58% |
| Payment fees | 274,609.50 | 2.18% | 15% |
| Refunds | 253,291.00 | 2.01% | 14% |
| Shipping | 202,391.00 | 1.61% | 11% |
| Reverse shipping | 35,396.00 | 0.28% | 2% |

## 3. Leakage by category

| Category | Orders | Gross | Leakage | Leakage % |
|---|---|---|---|---|
| Fashion | 763 | 2,222,988 | 349,989.54 | 15.7% |
| Electronics | 833 | 2,375,936 | 344,498.22 | 14.5% |
| Grocery | 698 | 2,093,714 | 314,626.79 | 15.0% |
| Home | 745 | 2,286,817 | 314,194.40 | 13.7% |
| Beauty | 663 | 1,970,033 | 260,292.85 | 13.2% |
| UNKNOWN | 571 | 1,649,927 | 250,339.70 | 15.2% |

The spread is only 2.5 points. The UNKNOWN bucket (257 products with blank category) is large enough that reclassifying it could change the ranking.

## 4. Monthly trend and drivers (% of gross)

| Month | Leakage % | Discounts | Refunds | Logistics | Fees |
|---|---|---|---|---|---|
| 2024-01 | 13.5 | 7.2 | 2.0 | 2.1 | 2.2 |
| 2024-02 | 17.3 | 9.3 | 4.0 | 1.8 | 2.2 |
| 2024-03 | 14.7 | 10.1 | 0.6 | 1.9 | 2.1 |
| 2024-04 | 12.1 | 5.8 | 2.4 | 1.9 | 2.1 |
| 2024-05 | 14.1 | 8.6 | 1.5 | 1.8 | 2.2 |
| 2024-06 | 13.5 | 6.8 | 2.6 | 2.0 | 2.2 |
| 2024-07 | 15.0 | 8.9 | 1.9 | 2.0 | 2.2 |
| 2024-08 | 12.6 | 6.7 | 2.0 | 1.7 | 2.2 |
| 2024-09 | 12.8 | 7.4 | 1.1 | 2.0 | 2.3 |
| 2024-10 | 16.7 | 11.0 | 1.4 | 1.9 | 2.3 |
| 2024-11 | 14.3 | 7.4 | 2.7 | 2.1 | 2.1 |
| 2024-12 | 17.9 | 12.3 | 1.9 | 1.6 | 2.1 |

- No upward trend. Logistics and fees are stable, so discounts and refunds explain the swings.
- **Feb** is refund-driven: 9 refunded orders (a normal count) averaging 4,682 vs about 3,052 overall, roughly 21k above the monthly average. With 1 to 11 refunded orders per month, one or two large refunds can move a month.
- **Oct and Dec** are discount-driven. Dec is broad across all discount types, led by bank offers (47,843 vs a monthly average of about 20.6k).
- Festival discounts are not clearly seasonal (similar levels in Feb, Mar, Jun and Dec), so a festive-season explanation is only weakly supported.

## 5. Concentration

542 of 1,647 products (32.9%) account for 80% of leakage. A classic 80/20 pattern would be about 20%, so leakage is widely spread. The top leaking products have only 2 to 7 orders each, so product rankings are noisy and are best used as a watch-list.

## 6. Discounts (1,068,254 on delivered orders)

| Discount type | Amount |
|---|---|
| BANKOFFER | 246,878 |
| COUPON | 248,519 |
| FESTIVAL | 243,075 |
| Blank (now UNKNOWN) | 329,782 |

| Stackable flag | Amount | Share |
|---|---|---|
| N | 418,189 | 39% |
| Y | 299,494 | 28% |
| Unknown | 350,571 | 33% |

Known types are about equal. The largest single bucket is the 31% with no type. Stackable discounts are the smallest share, so the stacking hypothesis is not supported.

## 7. Leakage outside the core definition

| Bucket | Amount | Note |
|---|---|---|
| Logistics cost on cancelled orders | 242,043 | clear leakage |
| Refunds with no recorded return | 188,027 (69 orders) | about 74% of confirmed refunds (253,291) |
| Logistics cost on shipped, pending and unknown-status orders | 249,794 / 244,301 / 240,190 | timing or data issues, not confirmed leakage |

Core 1,833,941.50 + 242,043 + 188,027 = about 2.26M, or **about 18% of gross**. Cost per order is about 55 in every status, so shipping cost does not vary with order status in this dataset.

## 8. Payment fees (delivered orders)

| Method | Orders | Gross | Fee | Fee % |
|---|---|---|---|---|
| COD | 827 | 2,410,099 | 84,354.60 | 3.50% |
| UNKNOWN (estimated) | 878 | 2,585,983 | 56,891.71 | 2.20% |
| CARD | 873 | 2,538,892 | 53,317.31 | 2.10% |
| WALLET | 823 | 2,409,078 | 48,181.56 | 2.00% |
| UPI | 872 | 2,655,363 | 31,864.32 | 1.20% |

COD produces about 31% of fee cost from about 19% of sales. If the unknown-method orders' true fee ranged from 1.2% to 3.5%, their fee would be about 31k to 91k instead of the estimated 57k.

## 9. Sensitivity: revenue definition

| Scenario | Orders | Gross | Leakage | Leakage % |
|---|---|---|---|---|
| DELIVERED only | 4,273 | 12,599,415 | 1,833,941.50 | 14.6% |
| DELIVERED + SHIPPED | 8,601 | 25,064,400 | 3,740,266.13 | 14.9% |

The rate barely moves. Dollar totals roughly double, so always state the definition used.

## 10. Lost shipments (verification item)

3,317 of 13,000 shipment records (25.5%) are marked LOST. About 3,083 orders have at least one LOST record, spread evenly across all order statuses, including **600 delivered orders worth 1,830,800**. A delivered order with a lost shipment is contradictory, so this is order value to verify against carrier records, not a confirmed loss.

## 11. Recommendations and scenarios

| # | Action | Evidence | Impact |
|---|---|---|---|
| 1 | Cap Oct and Dec discounts at about 7.8% of gross | Oct 11.0%, Dec 12.3% | about 84k |
| 2 | Require a return-received check before refunds | 188,027 refunded with no recorded return | up to 188k |
| 3 | Block dispatch on cancellation-requested orders | 242,043 on cancelled orders | each 25% cut is about 60.5k |
| 4 | Shift COD volume to UPI or prepaid | 3.5% vs 1.2% fee on 2.41M COD sales | 25% shift is about 13.9k; 50% is about 27.7k |
| 5 | Make discount type mandatory | 31% of discount value unattributed | makes 1.07M traceable |
| 6 | Reconcile carrier status with order status | 600 delivered orders with a LOST record | verification |

| Scenario | Assumptions | Recovered | Share of gross |
|---|---|---|---|
| Conservative | 10% of #2, 25% of #3, full #1, 25% COD shift | about 178k | about 1.4 points |
| Stretch | 50% of #2, 50% of #3, full #1, 50% COD shift | about 327k | about 2.6 points |

Scenarios are assumption-based, not forecasts. #2 and #3 sit outside the 14.6% core figure, so recovering them reduces the extended (about 18%) exposure.
