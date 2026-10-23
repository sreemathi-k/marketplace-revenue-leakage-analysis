# Marketplace Revenue Leakage & Gap Analysis (MySQL)

**Question:** Gross sales look healthy. How much of that revenue actually reaches the company, and where does the rest leak out?

**Answer:** **14.6%** of gross revenue (1.83M of 12.60M on delivered orders) leaks through discounts, refunds, logistics and payment fees. Discounts alone account for **58%** of the leakage. Counting anomalies outside the core definition, the exposure is about **18%**.

> Amounts are in the dataset's currency units (currency is not specified). The data is simulated; see [Limitations](#limitations).

---

## Dataset

Six tables, orders from 2024-01-01 to 2024-12-30.

| Table | Rows | Grain |
|---|---|---|
| raw_orders | 22,000 | one row per order |
| raw_products | 1,800 | one row per product |
| raw_discounts | 9,000 | many per order (7,417 distinct orders) |
| raw_logistics | 13,000 | many per order (9,810 distinct orders) |
| raw_returns | 4,000 | many per order (3,656 distinct orders) |
| raw_payment_fees | 6 | one row per payment method |

## Approach

```
raw_*  (all VARCHAR, loaded as-is, nothing rejected)
   |
   v
clean_*  (typed, standardized)  +  dq_quarantine  (every issue logged with its raw value)
   |
   v
revenue_leakage  (view, exactly one row per order)
   |
   v
analysis queries (waterfall, category, trend, Pareto, discounts, refunds, fees,profit)
```

Design choices that matter:

- **Fan-out control.** Discounts, logistics and returns have several rows per order. Each is rolled up to one row per order *before* joining, so revenue is never multiplied. All joins start from orders with `LEFT JOIN`.
- **Nothing silently dropped.** Bad values become NULL or `UNKNOWN`, and the original value is logged in `dq_quarantine`.
- **Reconciled to source.** The view has 22,000 rows (22,000 distinct orders). Its discount total (5,732,831) and shipping total (1,039,674) match the source tables exactly.

## Definitions

- **Revenue order:** `DELIVERED` with a valid quantity (4,273 orders).
- **Net revenue** = gross − discounts − refunds − shipping − reverse shipping − payment fee.
- **Leakage** = gross − net.
- **Refund** = what the customer paid (gross − discounts), counted once per order. The returns table has no refund amount.

Full list of rules: [docs/assumptions.md](docs/assumptions.md).

## Data quality (14 issue types logged)

| Issue | Rows affected | Treatment |
|---|---|---|
| Blank `order_status` | 4,438 orders | labeled `UNKNOWN`, not counted as revenue |
| `payment_method = INVALID` | 4,471 orders | labeled `UNKNOWN`, average fee (2.20%) applied |
| Invalid `quantity` | 488 orders | NULL, excluded from revenue totals |
| Invalid `shipping_cost` | 650 shipments | NULL, treated as 0 in sums and flagged |
| Invalid `cost_price` | 72 products | NULL, excluded from margin analysis only |
| `return_flag = X` | 1,297 returns | `UNKNOWN`, no leakage assigned |
| Blank `refund_status` | 1,011 returns | `UNKNOWN` |
| Returns on cancelled or pending orders | 1,580 returns | excluded from confirmed return leakage |
| Blank category | 257 products | `UNKNOWN` |
| Blank discount type | 2,298 discounts | `UNKNOWN` |
| Blank channel, refund mode, return reason, delivery status | 5,502 / 1,016 / 699 / 3,191 | `UNKNOWN` |

## Key findings

**1. Leakage waterfall (delivered orders, gross 12,599,415)**

| Component | Amount | % of gross | Share of leakage |
|---|---|---|---|
| Discounts | 1,068,254 | 8.48% | 58% |
| Payment fees | 274,609.50 | 2.18% | 15% |
| Refunds | 253,291 | 2.01% | 14% |
| Shipping | 202,391 | 1.61% | 11% |
| Reverse shipping | 35,396 | 0.28% | 2% |
| **Total leakage** | **1,833,941.50** | **14.6%** | 100% |

**2. Categories differ only a little.** Leakage runs from 13.2% (Beauty) to 15.7% (Fashion). Discount policy matters more than category.

**3. Monthly spikes have different causes.** Leakage ranges from 12.1% (Apr) to 17.9% (Dec). Feb (17.3%) is refund-driven: 9 refunds averaging 4,682 vs about 3,052 overall. Oct (11.0%) and Dec (12.3%) are discount-driven, with Dec bank offers (47,843) about 2.3 times their monthly average.

**3b. Leakage is widely spread.** 542 of 1,647 products (32.9%) account for 80% of leakage, so fixing a few products will not solve it. Policy-level changes will.

**4. Discount spend cannot be fully attributed.** 31% of discount value (329,782) has no discount type, and 33% has an unknown stackable flag. Stackable discounts are not the main driver (28% of discount value).

**5. Leakage outside the core definition**
- 242,043 of logistics cost on cancelled orders.
- 188,027 refunded on 69 delivered orders with no recorded return (about 74% as large as the 253,291 of confirmed refunds).
- Including both, exposure is about 2.26M, or **about 18% of gross**.

**6. COD is the costliest payment method.** It produces 31% of fee cost from 19% of sales (3.5% fee vs 1.2% for UPI).

**7. The result is robust to the revenue definition.** Counting SHIPPED orders as revenue moves leakage from 14.6% to 14.9%. Dollar totals roughly double (1.83M to 3.74M), so state which definition is used.

More detail and every table: [docs/findings.md](docs/findings.md).

## Recommendations (indicative impact)

| # | Action | Evidence | Impact |
|---|---|---|---|
| 1 | Cap Oct and Dec discounts at the other-months rate (about 7.8%) | Oct 11.0%, Dec 12.3% of gross | about 84k |
| 2 | Require a return-received check before refunds | 188,027 refunded with no recorded return | up to 188k |
| 3 | Block dispatch on cancellation-requested orders | 242,043 logistics cost on cancelled orders | each 25% cut is about 60.5k |
| 4 | Shift COD volume to UPI or prepaid | 3.5% vs 1.2% fee on 2.41M COD sales | 25% shift is about 13.9k |
| 5 | Make discount type mandatory | 31% of discount value is unattributed | makes 1.07M of spend traceable |
| 6 | Reconcile carrier status with order status | 600 delivered orders have a LOST shipment record (1.83M) | verification, not a savings figure |

Scenarios (assumption-based, not forecasts): **conservative about 178k (1.4 points of gross)** and **stretch about 327k (2.6 points)**. Assumptions are listed in [docs/findings.md](docs/findings.md).

## Limitations

- The dataset is **simulated**. Many categorical fields split almost evenly (for example, return reasons), so conclusions rest on dollar-weighted results, not on category shares.
- Only about 350 revenue orders fall in each month, so monthly swings can be noise. Treat them as patterns to investigate.
- Product-level rankings are noisy (the top leaking products have only 2 to 7 orders each).
- Refund amounts are derived as full amount paid, because the returns table has no refund value. Partial refunds cannot be measured.
- The fee for the 4,471 unknown-method orders is estimated at 2.20%. If the true rates ranged from 1.2% to 3.5%, fee leakage on delivered unknown-method orders could be about 31k to 91k instead of 57k.
- Missing shipping costs are treated as 0, so shipping leakage is understated by an unknown amount.
- Order status and shipment status contradict each other in places (for example, cancelled orders with shipping cost, delivered orders with LOST shipments). These are reported, not corrected.

## Repository structure

```
/data        source CSV files
/sql
  01_create_raw_tables.sql
  02_cleaning_data.sql
  03_revenue_leakage_view.sql
  04_analysis_queries.sql
  05_profit_analysis_queries.sql
/docs
  assumptions.md
  findings.md
README.md
```

## How to run

1. Use MySQL 8.0 or later (the project uses CTEs and window functions).
2. Create the database and load the six CSV files into the `raw_` tables (`01_create_raw_tables.sql`).
3. Run `02_cleaning_data.sql`, then `03_revenue_leakage_view.sql`.
4. Run the validation checks (row counts, discount and shipping totals tie to source), then `04_analysis_queries.sql`.

## SQL skills demonstrated

CTEs, window functions (`ROW_NUMBER`, `RANK`, `LAG`, running totals,STDDEV), multi-table joins with fan-out control, `EXISTS`, conditional aggregation (`CASE`), views, data cleaning and validation, reconciliation checks, regex-based type validation.

## Author

Sreemathi.K |www.linkedin.com/in/sreemathi-k-3baa60202| ksreemathi5@gmail.com



