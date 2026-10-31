-- =============================================================================
-- Cleanup for snowflake-dbt-medallion-warehouse. DESTRUCTIVE - read first.
--
-- Step 1 (read-only): confirm the schemas contain only this project's objects.
-- Expected: RAW_* tables in BRONZE, STG_* / INT_* views in SILVER,
--           DIM_* / FCT_* tables in GOLD. If you see anything else, STOP.
-- =============================================================================

select table_schema, table_name, table_type
from medallion.information_schema.tables
where table_schema in ('BRONZE', 'SILVER', 'GOLD')
order by table_schema, table_name;

-- Step 2: drop only the project objects (not the schemas or the database),
-- by running the generated statements after reviewing them.
select 'drop ' || iff(table_type = 'VIEW', 'view', 'table') || ' if exists medallion.'
       || table_schema || '.' || table_name || ';' as drop_statement
from medallion.information_schema.tables
where (table_schema = 'BRONZE' and startswith(table_name, 'RAW_'))
   or (table_schema = 'SILVER' and (startswith(table_name, 'STG_') or startswith(table_name, 'INT_')))
   or (table_schema = 'GOLD'   and (startswith(table_name, 'DIM_') or startswith(table_name, 'FCT_')))
order by table_schema, table_name;

-- Step 3 (optional, only if you created them with 01_snowflake_setup.sql and
-- nothing else uses them). Uncomment deliberately:
-- drop warehouse if exists medallion_wh;
-- drop role if exists medallion_transformer;
