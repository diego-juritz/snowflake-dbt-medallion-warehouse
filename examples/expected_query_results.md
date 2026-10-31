# Expected query results

Results of [`analyses/business_questions.sql`](../analyses/business_questions.sql)
against the committed sample data, captured from a real run on Snowflake
(dbt-core 1.12.6, dbt-snowflake 1.12.4, 2026-10-30).

Q1–Q5 were independently recomputed from the raw CSVs with
[`scripts/reference_metrics.py`](../scripts/reference_metrics.py) (plain Python,
no SQL) and match exactly. Because the data is deterministic, any change to
these numbers after a code change means business logic changed and should be
reviewed.

Definitions (see [design decisions](../docs/design_decisions.md#metric-definitions)):
gross sales = quantity × unit price; net sales = gross − discounts (tax
excluded); only `completed` orders count as sales; AOV = net sales / completed
orders.

## Q1. Monthly gross and net sales
| YEAR_MONTH | COMPLETED_ORDERS | GROSS_SALES | DISCOUNTS | NET_SALES |
|---|---|---|---|---|
| 2025-01 | 7 | 1552.29 | 6.99 | 1545.30 |
| 2025-02 | 6 | 4125.78 | 171.17 | 3954.61 |
| 2025-03 | 7 | 4417.27 | 6.90 | 4410.37 |
| 2025-04 | 5 | 1984.85 | 32.04 | 1952.81 |
| 2025-05 | 6 | 1759.84 | 2.69 | 1757.15 |
| 2025-06 | 8 | 4101.71 | 64.77 | 4036.94 |
| 2025-07 | 8 | 5505.80 | 131.92 | 5373.88 |
| 2025-08 | 4 | 3950.88 | 5.99 | 3944.89 |
| 2025-09 | 5 | 1612.93 | 125.50 | 1487.43 |
| 2025-10 | 4 | 2780.91 | 2.99 | 2777.92 |
| 2025-11 | 5 | 1526.85 | 46.68 | 1480.17 |

## Q2. Top 5 products by net sales
| PRODUCT_ID | PRODUCT_NAME | CATEGORY | UNITS_SOLD | NET_SALES |
|---|---|---|---|---|
| P006 | Standing Desk | Furniture | 22 | 9698.40 |
| P005 | Noise-Cancelling Headphones | Electronics | 26 | 5114.30 |
| P007 | Ergonomic Chair | Furniture | 15 | 4803.40 |
| P014 | Monitor Arm | Furniture | 30 | 3486.70 |
| P004 | 27in Monitor | Electronics | 10 | 2790.00 |

## Q3. Top 5 customers by net sales
| CUSTOMER_ID | FULL_NAME | COMPLETED_ORDERS | NET_SALES |
|---|---|---|---|
| C030 | Tomas Brennan | 5 | 4442.88 |
| C002 | Liam Novak | 4 | 2474.05 |
| C001 | Ava Reyes | 6 | 2202.52 |
| C007 | Ivy Silva | 3 | 2165.14 |
| C011 | Ruby Rossi | 3 | 1972.89 |

## Q4. Average order value
| COMPLETED_ORDERS | NET_SALES | AVERAGE_ORDER_VALUE |
|---|---|---|
| 65 | 32721.47 | 503.41 |

## Q5. Orders by status
| ORDER_STATUS | ORDERS | ORDER_VALUE_INCL_TAX | NET_AMOUNT_PAID | OUTSTANDING_AMOUNT |
|---|---|---|---|---|
| cancelled | 8 | 4421.80 | 0.00 | 0.00 |
| completed | 65 | 35339.28 | 35339.28 | 0.00 |
| pending | 7 | 3937.15 | 0.00 | 3937.15 |

## Q6. Net sales by category and month
| YEAR_MONTH | CATEGORY | NET_SALES |
|---|---|---|
| 2025-01 | Electronics | 1015.91 |
| 2025-01 | Furniture | 357.00 |
| 2025-01 | Home Office | 82.47 |
| 2025-01 | Stationery | 74.93 |
| 2025-01 | Uncategorized | 14.99 |
| 2025-02 | Accessories | 59.98 |
| 2025-02 | Electronics | 1994.94 |
| 2025-02 | Furniture | 1757.40 |
| 2025-02 | Stationery | 142.29 |
| 2025-03 | Accessories | 59.98 |
| 2025-03 | Electronics | 2249.86 |
| 2025-03 | Furniture | 1914.00 |
| 2025-03 | Home Office | 144.57 |
| 2025-03 | Stationery | 26.97 |
| 2025-03 | Uncategorized | 14.99 |
| 2025-04 | Accessories | 89.97 |
| 2025-04 | Electronics | 836.94 |
| 2025-04 | Furniture | 809.20 |
| 2025-04 | Home Office | 177.73 |
| 2025-04 | Stationery | 38.97 |
| 2025-05 | Accessories | 29.99 |
| 2025-05 | Electronics | 449.90 |
| 2025-05 | Furniture | 1227.00 |
| 2025-05 | Stationery | 50.26 |
| 2025-06 | Accessories | 80.98 |
| 2025-06 | Electronics | 2077.81 |
| 2025-06 | Furniture | 1798.20 |
| 2025-06 | Home Office | 79.95 |
| 2025-07 | Electronics | 1564.23 |
| 2025-07 | Furniture | 3528.10 |
| 2025-07 | Home Office | 246.48 |
| 2025-07 | Stationery | 35.07 |
| 2025-08 | Accessories | 53.99 |
| 2025-08 | Electronics | 1388.94 |
| 2025-08 | Furniture | 2452.00 |
| 2025-08 | Home Office | 31.98 |
| 2025-08 | Stationery | 17.98 |
| 2025-09 | Accessories | 29.99 |
| 2025-09 | Electronics | 49.98 |
| 2025-09 | Furniture | 1367.50 |
| 2025-09 | Stationery | 39.96 |
| 2025-10 | Accessories | 27.00 |
| 2025-10 | Electronics | 726.98 |
| 2025-10 | Furniture | 1796.00 |
| 2025-10 | Home Office | 201.96 |
| 2025-10 | Stationery | 25.98 |
| 2025-11 | Accessories | 29.99 |
| 2025-11 | Electronics | 229.94 |
| 2025-11 | Furniture | 982.10 |
| 2025-11 | Home Office | 163.08 |
| 2025-11 | Stationery | 48.07 |
| 2025-11 | Uncategorized | 26.99 |

## Q7. Data-quality summary
| CHECK_NAME | VALUE |
|---|---|
| raw customer records | 34 |
| distinct customers after dedup | 30 |
| orders with unknown customer | 1 |
| orders with a failed payment attempt | 11 |
| cancelled orders refunded | 2 |
| open exceptions | 1 |

Notes:

- No completed orders fall in December 2025: the last generated order is dated
  in late November.
- The orphan order `O0047` (net sales 1,450.50) is attributed to the
  "Unknown customer" member, so it is included in Q1, Q2, Q4 and Q6 but does
  not rank in the Q3 top 5.
- Q5 shows cancelled orders with 0.00 net paid: two were paid and fully
  refunded, three had only failed attempts, three had no payment events.
