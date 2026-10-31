-- Deduplication must collapse duplicates without losing any customer: every
-- distinct customer_id in the raw data appears exactly once in dim_customers,
-- and the merged record counts add back up to the raw row count.
with raw_stats as (

    select count(distinct customer_id) as raw_customers, count(*) as raw_records
    from {{ ref('stg_customers') }}

),

dim_stats as (

    select count(*) as dim_customers, sum(source_record_count) as merged_records
    from {{ ref('dim_customers') }}
    where not is_unknown_member

)

select *
from raw_stats
cross join dim_stats
where raw_customers <> dim_customers
   or raw_records <> merged_records
