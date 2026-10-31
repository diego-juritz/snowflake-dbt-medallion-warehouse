-- Grain: one row per customer_id (Type 1: latest version wins).
--
-- Deduplication rule:
--   1. latest source_updated_at wins;
--   2. on an exact timestamp tie, the record that appears later in the export
--      (higher source_record_id) wins. source_record_id is unique, so the
--      result is deterministic across runs.
with customers as (

    select * from {{ ref('stg_customers') }}

),

ranked as (

    select
        *,
        count(*) over (partition by customer_id)    as source_record_count
    from customers
    qualify row_number() over (
        partition by customer_id
        order by source_updated_at desc nulls last, source_record_id desc
    ) = 1

)

select
    customer_id,
    first_name,
    last_name,
    email,
    phone,
    country_code,
    signup_date,
    source_updated_at,
    source_record_id                                as winning_source_record_id,
    source_record_count
from ranked
