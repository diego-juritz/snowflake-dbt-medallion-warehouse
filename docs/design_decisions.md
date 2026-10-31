# Design decisions

## Why dbt Core (1.12)

dbt Core keeps the project runnable from any terminal with `pip install`, has no
platform dependency, and its test/doc/lineage features are what this project
is about. The project pins **dbt-core 1.12.6** and **dbt-snowflake 1.12.4**,
the newest Core releases when it was built. The dbt CLI now advertises "dbt
v2" (the Fusion-based engine) as the default for new installations. This
project deliberately stays on Core v1: Core is the documented, open-source
path for the Snowflake adapter. The YAML uses the 1.10+ conventions
(`data_tests:`, test `arguments:`, custom keys under `config.meta`), and
`dbt parse --show-all-deprecations` reports no deprecations, which is a
prerequisite for a later v2 migration. Running on v2 has **not** been tested.

## Why seeds instead of an ingestion service

Seeds make the raw zone reproducible from a clean clone with one command and
no extra infrastructure. **They are not an ingestion tool**: they load small
static CSVs, have no incremental loading, no schema-drift handling, no
retries, and no load auditing. In production, Bronze would be written by
Snowpipe, `COPY INTO`, Openflow, or a vendor connector. Models read Bronze
through `source()` rather than `ref()` to the seeds, so swapping the loader
does not require touching a model.

Every seed column is typed `VARCHAR` (`data/_seeds.yml`). This stops dbt's
type inference from silently reinterpreting raw text, such as mixed date
formats, before the Silver rules can see it.

### Ingestion metadata

The CSVs carry `_record_id` (row position in the export), `_source_file`, and
`_extracted_at`. `_extracted_at` is a **fixed, simulated export timestamp**
(`2026-01-01T00:00:00Z`) written by the generator. It is not the time the
data was loaded into Snowflake. A runtime `current_timestamp()` "loaded_at"
column was deliberately not added. It would change on every run, break
reproducibility, and imply a load audit trail that seeds do not provide.

## Why separate Bronze, Silver and Gold

- **Bronze** is the immutable audit copy. If a cleaning rule is wrong, the
  original text is still there.
- **Silver** holds every cleaning and business rule in one tested place.
  Staging models keep the source grain; intermediate models change grain
  (dedup, aggregation) and are named for what they do.
- **Gold** is shaped for consumers (star schema, surrogate keys, unknown
  member) and contains no cleaning logic.

## Materializations

| Models | Materialization | Reason |
|---|---|---|
| seeds | table | Required by `dbt seed`. `+full_refresh: true` reloads them completely. |
| `stg_*`, `int_*` | view | Tiny data, no storage, always current; Silver is cheap to recompute. |
| `dim_*`, `fct_*` | table | Consumers query Gold repeatedly; tables avoid recomputing the Silver chain per query. |

Incremental models were not used. At this data volume they would add
complexity (merge keys, late-arriving data, `--full-refresh` discipline)
without benefit.

## Customer deduplication (Type 1)

The raw customer export contains 34 records for 30 customers:

| customer_id | Raw records | Scenario | Winning record |
|---|---|---|---|
| C005 | 2 | older record with dirty values; newer record shows a move to FR | latest `updated_at` |
| C012 | 2 | two records with **identical** `updated_at` | higher `_record_id` (tie-breaker) |
| C020 | 3 | the latest-by-time record is not the last one in the file | latest `updated_at` (record 33), not the last row |

Rule (`int_customers_deduplicated`):
`row_number() over (partition by customer_id order by source_updated_at desc nulls last, source_record_id desc) = 1`.
`source_record_id` is unique (tested), so the result is deterministic.
`assert_customer_dedup_preserves_every_customer` checks that no customer is
lost and that merged record counts add back up to the raw row count. A unit
test pins the tie-breaker behavior.

SCD Type 2 (keeping C005's history in GB *and* FR) is out of scope and noted
as a follow-up.

## Metric definitions

| Metric | Definition |
|---|---|
| Gross sales | `quantity × unit_price` on the line (price charged, not current list price) |
| Discount | line `discount_amount` |
| Net sales | gross sales − discount. **Excludes tax.** |
| Order value (`order_total_amount`) | order net sales + order tax |
| Recognized sales | only orders with `order_status = 'completed'` (`is_revenue_recognized`) |
| Average order value | recognized net sales / number of completed orders |
| Net amount paid | Σ successful payments − Σ refunds |
| Outstanding amount | order value − net paid; forced to 0 for cancelled orders |

Status rules:

- **Order status**: source variants map to `completed`, `pending`, or
  `cancelled` (`complete`→`completed`, `canceled`→`cancelled`). Any other
  value becomes `unknown`, which fails `accepted_values`. A new status cannot
  slip through silently.
- **Payment status**: `success` = captured; `refunded` = money returned
  (positive amount, subtracted); `failed` = declined, never counted;
  `pending` = authorized, not captured, not counted as paid.
- **Cancelled orders** never count as sales, even if they were paid and then
  refunded.
- **Pending orders** are reported separately (Q5), not as sales.

## How the grain prevents double counting

An order has many lines **and** many payments. Joining raw payments to lines
would repeat each payment once per line. The fix is structural:

1. `int_payments_by_order` aggregates payments to one row per order.
2. `int_orders_enriched` aggregates lines to one row per order in a CTE.
3. Both aggregates join to the order header 1:1. `unique` tests on `order_id`
   in each model prove the 1:1 relationship.
4. `fct_order_items` carries no payment or tax columns at all.

`assert_fct_order_items_reconcile_with_fct_orders` checks that line-level net
sales sum to the order-level value per order. `assert_gold_net_sales_match_silver`
checks that Gold recognized sales equal an independent Silver computation.
No `DISTINCT` is used anywhere to hide duplicates.

## Handling invalid records

Records are **flagged, not discarded**:

- `int_order_exceptions` is an exception register: one row per order and issue
  type (`orphan_customer`, `unparseable_order_date`, `unknown_order_status`,
  `order_without_items`, `total_mismatch`).
- `exception_type` has an `accepted_values` test that allows only
  `orphan_customer`, the one issue intentionally present in the sample data.
  Any new type fails the build.
- The orphan order `O0047` (customer `C999` does not exist) stays in
  `fct_orders`. It points to the **Unknown customer** row in `dim_customers`
  (`customer_id = '-1'`) and keeps the original id in `source_customer_id`.
  Revenue totals stay complete and fact-to-dimension relationships stay valid.

### Controlled failure demo

The relationship test `stg_orders.customer_id → stg_customers.customer_id`
uses a configurable severity:

```yaml
config:
  severity: "{{ 'error' if var('strict_referential_integrity') else 'warn' }}"
```

- Default `dbt build`: 1 warning (`O0047`), build succeeds.
- `make strict-test`, i.e.
  `dbt test --select stg_orders --vars '{strict_referential_integrity: true}'`:
  the test fails with `Got 1 result, configured to fail if != 0` and dbt exits
  with code 1.

To troubleshoot, compile the failing test
(`target/compiled/.../relationships_stg_orders_*.sql`) and run it, or query
`int_order_exceptions`. Both identify `O0047` / `C999`.

## Tests that encode assumptions, not universal truths

`assert_order_settlement_matches_status` requires completed orders to be fully
paid and cancelled orders to keep no money. That is true in this scenario
(prepaid e-commerce). A business with invoicing, partial shipments, or
partial cancellations would need a different rule. The test's header comment
says so.

## Surrogate keys

`dbt_utils.generate_surrogate_key` (an MD5 hash of the business key) gives
stable, reproducible keys with no sequence state, so rebuilding Gold
produces identical keys. `dim_date.date_key` is an integer `YYYYMMDD`. The
trade-off: MD5 strings are wider than integers, which is irrelevant at this
scale.

## Credentials and environment separation

- `profiles.yml` is gitignored. `profiles.yml.example` only reads environment
  variables, and `.env.example` holds placeholders.
- Key-pair (JWT) authentication is used. Locally, a key **file path** outside
  the repo; in CI, the PEM content comes from a GitHub secret.
- `DBT_SCHEMA_PREFIX` isolates developers and CI runs. It is validated against
  `^[A-Z][A-Z0-9_]{0,40}$` because it ends up in DDL.
- CI drops its schemas through `drop_ci_schemas`, which refuses to run unless
  the prefix starts with `CI_`.

**Deviation in the reference run:** the Snowflake validation for this
repository ran as `ACCOUNTADMIN` in a personal trial account, by explicit
choice of the account owner. The recommended setup is the least-privilege
role in [`setup/01_snowflake_setup.sql`](../setup/01_snowflake_setup.sql).
That script was reviewed and its `CREATE` statements compile, but it was not
executed for this run.

## What would change in production

- Real ingestion (Snowpipe / Openflow / connector) writing Bronze, with source
  freshness checks (`loaded_at_field`) on real load timestamps.
- Incremental Gold facts with a merge key and late-data handling.
- SCD Type 2 for customers (dbt snapshots or a CDC-driven model).
- Tax allocated to lines if line-level tax reporting is needed.
- Separate dev / CI / prod databases, with deploys gated by review and run by
  a scheduler (dbt Projects on Snowflake, Airflow, or similar).
- Masking policies on PII columns (email, phone) and role-based access to Gold.
- Resource monitors and query tags for cost attribution (tags already set:
  `medallion_warehouse_dev`, `medallion_warehouse_ci`).
