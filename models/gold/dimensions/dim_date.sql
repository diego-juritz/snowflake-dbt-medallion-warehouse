-- Grain: one row per calendar day in a fixed, configurable range.
-- The range comes from project vars (not from the data or current_date), so the
-- table is identical on every run.
{% set start_date = var('dim_date_start') %}
{% set end_date = var('dim_date_end') %}

with spine as (

    {{ dbt_utils.date_spine(
        datepart='day',
        start_date="to_date('" ~ start_date ~ "')",
        end_date="dateadd(day, 1, to_date('" ~ end_date ~ "'))"
    ) }}

)

select
    to_number(to_char(date_day, 'YYYYMMDD'))        as date_key,
    cast(date_day as date)                          as date_day,
    year(date_day)                                  as calendar_year,
    quarter(date_day)                               as calendar_quarter,
    month(date_day)                                 as calendar_month,
    monthname(date_day)                             as month_short_name,
    to_char(date_day, 'YYYY-MM')                    as year_month,
    cast(date_trunc('month', date_day) as date)     as month_start_date,
    dayofweekiso(date_day)                          as iso_day_of_week,
    dayname(date_day)                               as day_short_name,
    dayofweekiso(date_day) in (6, 7)                as is_weekend
from spine
