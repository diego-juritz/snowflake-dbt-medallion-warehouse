-- =============================================================================
-- One-time Snowflake setup for snowflake-dbt-medallion-warehouse.
--
-- Review before running. Run as a role allowed to create roles, warehouses and
-- databases (typically SECURITYADMIN + SYSADMIN, or ACCOUNTADMIN in a personal
-- trial account). dbt itself should then run as MEDALLION_TRANSFORMER, which
-- has no account-level privileges.
--
-- Replace <YOUR_USER> before running. Never put credentials in this file.
-- Creating and running a warehouse consumes Snowflake credits.
-- =============================================================================

use role sysadmin;

-- Small, auto-suspending warehouse dedicated to this project.
create warehouse if not exists medallion_wh
    warehouse_size = 'XSMALL'
    auto_suspend = 60
    auto_resume = true
    initially_suspended = true
    comment = 'snowflake-dbt-medallion-warehouse (dev)';

create database if not exists medallion comment = 'snowflake-dbt-medallion-warehouse';
create schema if not exists medallion.bronze;
create schema if not exists medallion.silver;
create schema if not exists medallion.gold;

use role securityadmin;

create role if not exists medallion_transformer
    comment = 'dbt runtime role for the MEDALLION project';
grant role medallion_transformer to role sysadmin;

grant usage   on warehouse medallion_wh to role medallion_transformer;
grant usage   on database medallion     to role medallion_transformer;
-- Lets CI create its own isolated CI_<run>_BRONZE/SILVER/GOLD schemas.
grant create schema on database medallion to role medallion_transformer;

-- dbt creates and replaces tables/views inside the three layer schemas.
grant usage, create table, create view on schema medallion.bronze to role medallion_transformer;
grant usage, create table, create view on schema medallion.silver to role medallion_transformer;
grant usage, create table, create view on schema medallion.gold   to role medallion_transformer;

grant role medallion_transformer to user <YOUR_USER>;

-- Optional: a dedicated key-pair service user for GitHub Actions.
-- Generate the key pair locally (see README), then paste ONLY the public key:
-- use role securityadmin;
-- create user if not exists medallion_ci_svc
--     type = service
--     default_role = medallion_transformer
--     default_warehouse = medallion_wh
--     rsa_public_key = '<PUBLIC_KEY_WITHOUT_HEADER_LINES>';
-- grant role medallion_transformer to user medallion_ci_svc;

-- Optional cost guardrail (requires ACCOUNTADMIN):
-- use role accountadmin;
-- create resource monitor if not exists medallion_rm
--     with credit_quota = 5 frequency = monthly start_timestamp = immediately
--     triggers on 90 percent do suspend;
-- alter warehouse medallion_wh set resource_monitor = medallion_rm;
