-- Grain: one row per customer (Type 1), plus one "Unknown customer" member
-- that facts reference when an order's customer_id has no match.
with customers as (

    select * from {{ ref('int_customers_deduplicated') }}

),

known as (

    select
        {{ dbt_utils.generate_surrogate_key(['customer_id']) }}         as customer_key,
        customer_id,
        first_name,
        last_name,
        trim(coalesce(first_name, '') || ' ' || coalesce(last_name, ''))  as full_name,
        email,
        phone,
        coalesce(country_code, 'UNKNOWN')                               as country_code,
        signup_date,
        source_record_count,
        false                                                           as is_unknown_member
    from customers

),

unknown_member as (

    select
        {{ dbt_utils.generate_surrogate_key(["'" ~ var('unknown_member_id') ~ "'"]) }} as customer_key,
        '{{ var("unknown_member_id") }}'            as customer_id,
        cast(null as varchar)                       as first_name,
        cast(null as varchar)                       as last_name,
        'Unknown customer'                          as full_name,
        cast(null as varchar)                       as email,
        cast(null as varchar)                       as phone,
        'UNKNOWN'                                   as country_code,
        cast(null as date)                          as signup_date,
        0                                           as source_record_count,
        true                                        as is_unknown_member

)

select * from known
union all
select * from unknown_member
