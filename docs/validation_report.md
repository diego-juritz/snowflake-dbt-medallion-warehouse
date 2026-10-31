# Validation report

Environment of the reference run (2026-10-30): macOS, Python 3.12 virtualenv,
dbt-core 1.12.6, dbt-snowflake 1.12.4, dbt_utils 1.4.1. Snowflake database
`MEDALLION`, X-Small Gen2 warehouse `COMPUTE_WH`, role `ACCOUNTADMIN` (a
personal trial account, chosen by the account owner; see
[limitations](#limitations-and-follow-ups)). The project was built with
Cortex Code; every result below comes from a command that was actually run.

Status legend: **passed**, **failed**, **not run**.

| # | Validation step | Command or method | Result | Evidence | Limitation / follow-up |
|---|---|---|---|---|---|
| 1 | Pre-flight: target schemas empty | `INFORMATION_SCHEMA.TABLES` on `MEDALLION` | passed | 0 objects in BRONZE/SILVER/GOLD before the first run | — |
| 2 | Sample data is deterministic | `generate_sample_data.py` twice + `shasum` diff; `--check` | passed | identical hashes; "All CSVs match" | — |
| 3 | CSV headers, keys, references, totals | `scripts/validate_sample_data.py` | passed | customers=34, products=15, orders=80, order_items=189, payments=89; only expected orphan O0047 | — |
| 4 | Python syntax | `python -m py_compile scripts/*.py` | passed | no output | No linter (ruff) run |
| 5 | YAML syntax | `yaml.safe_load` on all 10 project YAML files | passed | "yaml ok 10" | — |
| 6 | GitHub Actions workflow | `actionlint` 1.7.7 | passed | no findings | — |
| 7 | dbt dependency resolution | `dbt deps` | passed | dbt_utils 1.4.1 installed; `package-lock.yml` generated | — |
| 8 | Connectivity | `dbt debug` | passed | "All checks passed!" | — |
| 9 | Parse + deprecations | `dbt parse --no-partial-parse --show-all-deprecations` | passed | no deprecation warnings | First attempt **failed**: unquoted `Grain: …` descriptions were invalid YAML; fixed by quoting |
| 10 | Static CI job, no credentials | `dbt parse --target ci --warn-error` in `env -i` with placeholder values | passed | exit 0; `dbt ls` lists 127 nodes | Proves parse needs no connection; not a substitute for execution |
| 11 | Schema naming | inspected `dbt build` log; `DBT_SCHEMA_PREFIX=CI_LOCAL_1` run | passed | objects in `BRONZE`/`SILVER`/`GOLD`; prefixed run used `CI_LOCAL_1_*` | — |
| 12 | Prefix validation guard | `DBT_SCHEMA_PREFIX="bad;drop" dbt parse` | passed | compiler error "DBT_SCHEMA_PREFIX must match …" | — |
| 13 | CI drop-macro guard | `DBT_SCHEMA_PREFIX=PROD_X dbt run-operation drop_ci_schemas` | passed | refused: "only runs with … CI_" | — |
| 14 | Full pipeline on Snowflake | `dbt build` | passed | `PASS=126 WARN=1 ERROR=0 SKIP=0 TOTAL=127` (5 seeds, 14 models, 105 data tests, 3 unit tests) | First attempt: `dim_date` **failed** (Jinja whitespace control merged SQL into a comment); fixed |
| 15 | Clean rebuild after all edits | `dbt clean && dbt deps && dbt build` | passed | `PASS=126 WARN=1 ERROR=0` | — |
| 16 | Intentional warning is the orphan order | `int_order_exceptions` query | passed | 1 row: `O0047 orphan_customer customer_id C999 …` | — |
| 17 | Controlled failure demo | `dbt test --select stg_orders --vars '{strict_referential_integrity: true}'` | passed (fails as designed) | `FAIL 1 relationships_stg_orders_customer_id…`, exit code 1 | — |
| 18 | Isolated CI-style run + cleanup | `DBT_SCHEMA_PREFIX=CI_LOCAL_1 dbt build`, then `drop_ci_schemas` | passed | `PASS=126 WARN=1 ERROR=0`; `SHOW SCHEMAS` afterwards shows only BRONZE, GOLD, PUBLIC, SILVER | Run locally, not on GitHub |
| 19 | Edge-case spot checks | ad hoc SQL on `dim_customers`, `dim_products`, `fct_orders` | passed after fix | dedup picks C005→FR, C012→record 32, C020→record 33; categories normalized; P013 → Uncategorized | First check **failed**: `INITCAP` gave `O'brien`; fixed + unit test added |
| 20 | Business metrics, independent recomputation | `scripts/reference_metrics.py` vs Snowflake output of `analyses/business_questions.sql` | passed | Q1–Q5 identical to the cent (e.g. 65 completed orders, net 32,721.47, AOV 503.41) | Q6/Q7 not independently recomputed |
| 21 | Analyses compile | `dbt compile --select business_questions` | passed | 7 statements executed on Snowflake | — |
| 22 | Docs generation | `dbt docs generate` | passed | `catalog.json` written | `docs serve` not exercised |
| 23 | Setup SQL | compile-only for `CREATE WAREHOUSE`, `CREATE ROLE`, `CREATE USER … TYPE = SERVICE` | passed | "SQL compiled successfully" | `GRANT` statements could not be compile-checked (validator limitation); setup script **not executed** |
| 24 | Cleanup SQL | ran read-only steps 1–2 | passed after fix | generator matches 19 project objects | First version **failed** silently (`LIKE 'RAW\\_%'` matched 0; Snowflake has no default LIKE escape); fixed with `startswith()`. DROP statements not executed |
| 25 | Secrets / unsafe content | regex scan of the 54 files that would be committed; `git check-ignore` | passed | 0 hits for account id, keys, local paths, tokens; `profiles.yml`, `.venv`, `target`, `logs`, `dbt_packages`, `prompt.txt` ignored | Regex scan, not a dedicated scanner (e.g. gitleaks) |
| 26 | Internal Markdown links | script resolving relative links | passed | 0 broken after this report was added | External links checked separately: 10/10 returned HTTP 200 |
| 27 | README counts and commands | `dbt ls` per resource type | passed after fix | 5 seeds, 14 models, 105 data tests, 3 unit tests | README first said 108; corrected |
| 28 | GitHub Actions on GitHub | — | not run | Repository not pushed (awaiting approval) | Run after publishing; Snowflake job needs secrets + `SNOWFLAKE_CI_ENABLED` |
| 29 | Least-privilege role end to end | — | not run | Owner chose to run as ACCOUNTADMIN | Run `setup/01_snowflake_setup.sql`, then `dbt build` as `MEDALLION_TRANSFORMER` |

## Issues found and fixed

1. Invalid YAML: descriptions containing `": "` were parsed as mappings.
   Quoted them.
2. `dim_date` compile error: `{%- … -%}` removed the newline that ended a SQL
   comment. Removed the whitespace-control dashes.
3. Name casing: Snowflake `INITCAP` does not treat `'` as a delimiter by
   default (`O'Brien` → `O'brien`). Now `initcap(x, ' ''-')`, with unit test
   `stg_customers_cleans_names_emails_and_blanks`.
4. Cleanup query matched nothing because of `LIKE` escaping. Replaced with
   `startswith()`.
5. The generator contained a branch that never ran ("December orders are
   pending"; no December orders exist). Removed; `--check` confirmed the CSVs
   are byte-identical.
6. README test count corrected from 108 to 105.

## Cost evidence

`INFORMATION_SCHEMA.QUERY_HISTORY` shows 694 queries tagged
`medallion_warehouse_dev`, about 154 s of total elapsed time, across every
build in the session (including failed attempts and the isolated run). This
is not a credit figure: billing also depends on warehouse resume minimums and
idle time before auto-suspend.

## Limitations and follow-ups

- Execute the least-privilege setup and re-run `dbt build` with
  `MEDALLION_TRANSFORMER` (step 29).
- After publishing, confirm the static CI job on GitHub. Optionally configure
  secrets and enable the Snowflake job (step 28).
- Optional: add `ruff` and a dedicated secret scanner to CI.
