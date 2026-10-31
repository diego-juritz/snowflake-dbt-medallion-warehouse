{#-
    Drop the schemas created by one CI run. Used only by the GitHub Actions
    workflow after an integration run:

        dbt run-operation drop_ci_schemas --target ci

    Guardrails: it refuses to run unless DBT_SCHEMA_PREFIX starts with "CI_",
    and it only drops the three layer schemas for that exact prefix, so it can
    never touch BRONZE / SILVER / GOLD or a developer's schemas.
-#}
{% macro drop_ci_schemas() %}
    {% set prefix = env_var('DBT_SCHEMA_PREFIX', '') | trim | upper %}
    {% if not prefix.startswith('CI_') %}
        {{ exceptions.raise_compiler_error(
            "drop_ci_schemas only runs with a DBT_SCHEMA_PREFIX starting with CI_ (got '" ~ prefix ~ "')") }}
    {% endif %}
    {% for layer in ['bronze', 'silver', 'gold'] %}
        {% set schema_name = medallion_layer_schema(layer) %}
        {% do log("Dropping " ~ target.database ~ "." ~ schema_name, info=true) %}
        {% do run_query("drop schema if exists " ~ adapter.quote(target.database) ~ "." ~ schema_name) %}
    {% endfor %}
{% endmacro %}
