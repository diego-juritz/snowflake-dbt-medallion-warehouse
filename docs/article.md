# Building a Modern Snowflake Data Warehouse with dbt and Cortex Code

*Draft for editorial review. Repository:
<https://github.com/diego-juritz/snowflake-dbt-medallion-warehouse>
(link becomes valid once the repository is published).*

## The problem

Most "modern data stack" tutorials stop at the point where the work gets
interesting. They load a clean CSV, write one `SELECT`, and call it a
warehouse. Real e-commerce data looks different. Customers are exported
twice with different values. Order statuses arrive as `Completed`,
`complete`, and `COMPLETED`. One order has three payment events, one of them
failed. Somebody cancels after paying and gets refunded. If you join order
lines to payments naively, revenue silently doubles.

This project builds a small warehouse that answers ordinary business
questions: monthly gross and net sales, top products and customers, average
order value, and orders by status. It treats those messy cases as first-class
requirements. It runs on Snowflake with dbt Core, follows a Medallion layout,
and ends in a star schema. I built it with Cortex Code (CoCo), Snowflake's
AI coding assistant, and I'll be specific about where that helped and where
human review was still required.

## Architecture

```
data/*.csv ──dbt seed──▶ BRONZE.raw_*  ──source()──▶ SILVER.stg_* ──▶ SILVER.int_* ──▶ GOLD.dim_* / fct_*
```

Everything lives in one database, `MEDALLION`, with one schema per layer:

- **Bronze** is an untouched copy of the export. Every seed column is
  `VARCHAR` ([`data/_seeds.yml`](../data/_seeds.yml)), so dbt's type inference
  cannot quietly reinterpret `2025/03/05` before a rule decides what it means.
- **Silver** holds every cleaning and business rule. `stg_*` views keep the
  source grain. `int_*` views change it: deduplication, aggregation to order
  grain, and an exception register.
- **Gold** is the star schema consumers query, materialized as tables.

Two choices are worth defending up front.

**Seeds are not ingestion.** `dbt seed` loads static CSVs. It has no
incremental loads, no schema-drift handling, and no load auditing. I use it
only because it makes the raw zone reproducible from a clean clone. Models
read Bronze through `source()` rather than `ref()` to the seeds, so replacing
the loader with Snowpipe or a connector doesn't touch a single model.

**Exact schema names.** dbt's default would create `PUBLIC_BRONZE`. A short
`generate_schema_name` override
([`macros/generate_schema_name.sql`](../macros/generate_schema_name.sql)) maps
layers to `BRONZE`, `SILVER`, `GOLD`. An optional `DBT_SCHEMA_PREFIX`
produces isolated `DEV_JDOE_*` or `CI_<run>_*` schemas. Because that value
ends up in DDL, the macro validates it against `^[A-Z][A-Z0-9_]{0,40}$`.

## The dataset

A stdlib-only Python generator
([`scripts/generate_sample_data.py`](../scripts/generate_sample_data.py))
produces 30 customers (34 raw records), 15 products, 80 orders, 189 lines,
and 89 payment events. It uses a fixed random seed, integer-cent arithmetic,
and no wall-clock values; `--check` proves the committed CSVs are
byte-identical to a fresh run. The edge cases are deliberate: three
duplicated customers (one with an exact timestamp tie), padded and mis-cased
names, ten spellings of three order statuses, two date formats, a missing
category, split-tender payments, failed-then-retried payments, paid-then-
refunded cancellations, and one order pointing at a customer that does not
exist. The [data dictionary](data_dictionary.md) lists each case and how it is
handled.

## Bronze → Silver → Gold

Staging is deliberately boring. Order status mapping is a `case` expression
with an explicit fallback:

```sql
case
    when raw_status in ('completed', 'complete') then 'completed'
    when raw_status in ('pending') then 'pending'
    when raw_status in ('cancelled', 'canceled') then 'cancelled'
    else 'unknown'
end as order_status
```

The `else 'unknown'` matters. An `accepted_values` test rejects `unknown`, so
a new upstream status breaks the build instead of falling into the wrong
bucket. Dates use two explicit `try_to_date` formats, and anything else
becomes NULL and fails `not_null`. I don't let Snowflake guess `04/03/2025`.

Customer deduplication is Type 1, with a rule that is boring on purpose and
deterministic:

```sql
qualify row_number() over (
    partition by customer_id
    order by source_updated_at desc nulls last, source_record_id desc
) = 1
```

`source_record_id` is the row's position in the export and is tested
`unique`, so ties always resolve the same way. A unit test pins the tie case.
A singular test checks that deduplication loses no customer and that merged
record counts add back up to the raw row count.

## Declaring the grain

Before writing Gold, I fixed the grains:

| Fact | Grain |
|---|---|
| `fct_orders` | one row per order |
| `fct_order_items` | one row per order line |

The trap in this domain is that an order has *many lines and many payments*.
`int_payments_by_order` collapses payments to one row per order;
`int_orders_enriched` does the same for lines in a CTE; both then join the
order header 1:1, with `unique` tests on `order_id` proving it. Tax and
payments exist only on `fct_orders`, so nobody can sum them from the line
fact. No `DISTINCT` appears anywhere. It would hide exactly the kind of
duplication the tests are meant to catch.

Metrics are written down before they are coded
([design decisions](design_decisions.md#metric-definitions)):
gross = quantity × unit price; net = gross − discounts, **excluding tax**;
only `completed` orders count as sales; AOV = net sales / completed orders.

The orphan order is kept, not dropped. It appears in an exception register
(`int_order_exceptions`) and in `fct_orders`, pointing at an explicit
"Unknown customer" row in `dim_customers`. Totals stay complete, and every
fact-to-dimension relationship test still passes.

## Tests that protect something

The suite has 105 data tests and 3 unit tests. The interesting ones are
the six singular tests in [`tests/`](../tests):

- **Order totals reconcile:** source `order_total` = Σ line net + tax.
- **Line fact reconciles to order fact:** per-order line sums equal
  `fct_orders`. This is the fan-out guard.
- **Gold equals Silver:** recognized net sales match an independent Silver
  computation.
- **Payments never exceed the order**, and refunds never exceed captures.
- **Settlement matches status:** completed orders are fully paid and
  cancelled orders keep no money. This is a *scenario* assumption (prepaid
  e-commerce), and the test's header says so. A business with invoicing
  would need a different rule.
- **Dedup preserves every customer.**

There is also a controlled failure. The relationship test from orders to
customers has a configurable severity:

```yaml
severity: "{{ 'error' if var('strict_referential_integrity') else 'warn' }}"
```

The default build passes with one warning. With
`--vars '{strict_referential_integrity: true}'` it fails with exit code 1 and
names the orphan order. Readers can see the failure without having to break
anything.

## How Cortex Code was used

I gave CoCo, running in VS Code, a long written specification: architecture,
layers, edge cases, testing and CI expectations, and security and cost rules.
It had shell, file, and Snowflake SQL access in the session. In practice it:

- inspected the empty repository, local Python and tooling, existing dbt
  profiles (and left an unrelated one untouched), and the target database,
  confirming that `MEDALLION.BRONZE/SILVER/GOLD` existed and were empty
  before creating anything;
- checked the current dbt release (Core 1.12.6, adapter 1.12.4) and the dbt
  deprecations reference, then wrote YAML in the current `arguments:` /
  `config.meta` style;
- scaffolded the generator, the models, the YAML, the tests, the CI
  workflow, and the documentation;
- ran `dbt build` against Snowflake, read the failures, and fixed them;
- spot-checked results with ad hoc SQL and wrote an independent Python
  recomputation of the headline metrics.

Some decisions were mine, not the assistant's. Two examples: running as
`ACCOUNTADMIN` in my personal trial account (the repo ships a least-privilege
setup script instead), and not choosing a license yet.

## What needed human-level review

These are the actual problems found during the session. All of them came up
in generated code.

1. **YAML that looked fine.** Descriptions like
   `description: Typed product catalog. Grain: one row per product.` are
   invalid YAML because `: ` starts a mapping. `dbt parse` caught it
   immediately. Trivial, but a reminder that "looks right" isn't a check.
2. **Jinja whitespace control ate SQL.** In `dim_date`,
   `{%- set ... -%}` stripped the newline after a SQL comment, so
   `with spine as (` ended up *inside* the comment. Snowflake reported an
   "unexpected 'select'" at line 146 of the compiled file. The fix was to
   remove the dashes. The lesson: read `target/run/...`, not the source.
3. **A green build with a wrong answer.** After the first fully passing
   build, a manual look at `dim_customers` showed `Theo O'brien`. Snowflake's
   `INITCAP` doesn't treat the apostrophe as a word boundary by default. The
   build was green (125 passing nodes plus the one expected warning) because
   no test asserted name casing. The fix passes
   explicit delimiters (`initcap(name, ' ''-')`), plus a unit test that
   asserts `O'Brien-Smith`. This one matters most: **tests only cover what
   someone thought to assert**, and looking at the output is still part of
   the job.
4. **A cleanup script that would have done nothing.** The generated cleanup
   query filtered with `like 'RAW\\_%'`. Snowflake's `LIKE` has no default
   escape character, so it matched zero rows. Running the read-only half of
   the script showed `0`; the fix uses `startswith()`. A destructive script
   that silently does nothing is better than the reverse, but it still wasn't
   correct.
5. **A wrong number in the README.** The first README said "108 data tests".
   Counting with `dbt ls` gave 105. Small, but exactly the kind of claim
   readers copy.

There was also a validation limit rather than a bug. Compile-only checking of
the setup script's `GRANT` statements failed inside the validator itself, so
those statements are reported as reviewed, not as validated.

The pattern across all five: the assistant was fast at producing plausible,
mostly correct code and at running the feedback loop. Correctness came from
the loop itself: parse, build, look at the data, recompute independently.
Generation alone didn't provide it.

## Validation and outcomes

Everything below actually ran ([validation report](validation_report.md)):

- `dbt build` on Snowflake: **PASS=126, WARN=1 (intentional), ERROR=0**
  across 5 seeds, 14 models, 105 data tests, and 3 unit tests.
- The same build in isolated `CI_LOCAL_1_*` schemas, followed by the guarded
  drop macro. The schemas were gone afterwards.
- Strict mode fails as designed (exit code 1, one row).
- The headline metrics match a plain-Python recomputation from the raw CSVs
  to the cent: 65 completed orders, net sales 32,721.47, AOV 503.41.
- The static CI job (placeholder env, no connection) passes, and actionlint
  passes on the workflow.

What has *not* run: the GitHub Actions workflow on GitHub itself, and the
least-privilege role setup end to end.

## Trade-offs and lessons

- **Views in Silver, tables in Gold** is right at this size and would be
  revisited at volume (incremental facts, clustering).
- **Type 1 customers** keep the example focused. C005 moved from GB to FR,
  and that history is lost. That's the topic for an SCD Type 2 follow-up.
- **Tax stays at order grain.** Allocating it to lines is a business
  decision (rounding, per-line rates), not a SQL detail.
- **Flag, don't drop** costs one extra model and one unknown-member row, and
  it saves the "why don't the totals match finance?" conversation.
- **An AI assistant shortens the distance to a first draft.** It doesn't
  shorten the distance to *correct*. Budget the review time.

## Reproduce it

```bash
git clone https://github.com/diego-juritz/snowflake-dbt-medallion-warehouse
cd snowflake-dbt-medallion-warehouse
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cp .env.example .env && cp profiles.yml.example profiles.yml   # fill .env
set -a && source .env && set +a && source .venv/bin/activate
dbt deps && dbt debug && dbt build
```

Running it consumes Snowflake credits. Use an X-Small, auto-suspending
warehouse, and see the README's cost and cleanup sections.

## What production would need

Real ingestion with load timestamps and freshness checks; incremental facts;
SCD Type 2; separate dev/CI/prod databases with reviewed deployments;
masking policies on email and phone; resource monitors; and an orchestrator
or dbt Projects on Snowflake for scheduling.

## References

- dbt: [installation](https://docs.getdbt.com/docs/core/installation-overview),
  [Snowflake setup](https://docs.getdbt.com/docs/core/connect-data-platform/snowflake-setup),
  [custom schemas](https://docs.getdbt.com/docs/build/custom-schemas),
  [data tests](https://docs.getdbt.com/docs/build/data-tests),
  [unit tests](https://docs.getdbt.com/docs/build/unit-tests),
  [deprecations](https://docs.getdbt.com/reference/deprecations)
- Snowflake: [key-pair authentication](https://docs.snowflake.com/en/user-guide/key-pair-auth),
  [warehouse considerations](https://docs.snowflake.com/en/user-guide/warehouses-considerations),
  [resource monitors](https://docs.snowflake.com/en/user-guide/resource-monitors),
  [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
