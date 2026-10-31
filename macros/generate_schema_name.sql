{#-
    Map each layer's custom schema (bronze / silver / gold) to an exact
    Snowflake schema name instead of dbt's default "<target_schema>_<custom>".

        DBT_SCHEMA_PREFIX unset  ->  BRONZE, SILVER, GOLD
        DBT_SCHEMA_PREFIX=DEV_DJ ->  DEV_DJ_BRONZE, DEV_DJ_SILVER, DEV_DJ_GOLD

    The database always comes from the active target, so nothing here is
    hardcoded to an environment. Nodes without a custom schema fall back to
    target.schema.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema | trim }}
    {%- else -%}
        {{ medallion_layer_schema(custom_schema_name) }}
    {%- endif -%}
{%- endmacro %}


{% macro medallion_layer_schema(layer) -%}
    {%- set prefix = env_var('DBT_SCHEMA_PREFIX', '') | trim | upper -%}
    {%- if prefix and not modules.re.match('^[A-Z][A-Z0-9_]{0,40}$', prefix) -%}
        {{ exceptions.raise_compiler_error(
            "DBT_SCHEMA_PREFIX must match ^[A-Z][A-Z0-9_]{0,40}$, got: " ~ prefix) }}
    {%- endif -%}
    {{ (prefix ~ '_' if prefix else '') ~ (layer | trim | upper) }}
{%- endmacro %}
