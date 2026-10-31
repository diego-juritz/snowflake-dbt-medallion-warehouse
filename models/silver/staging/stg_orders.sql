with source as (

    select * from {{ source('bronze', 'raw_orders') }}

),

typed as (

    select
        try_to_number(_record_id)                       as source_record_id,
        upper(trim(order_id))                           as order_id,
        upper(trim(customer_id))                        as customer_id,
        -- The source mixes ISO dates and YYYY/MM/DD. Anything else becomes NULL
        -- and fails the not_null test rather than being guessed.
        coalesce(
            try_to_date(trim(order_date), 'YYYY-MM-DD'),
            try_to_date(trim(order_date), 'YYYY/MM/DD')
        )                                               as order_date,
        lower(trim(status))                             as raw_status,
        try_to_number(trim(tax_amount), 12, 2)          as tax_amount,
        try_to_number(trim(order_total), 12, 2)         as source_order_total,
        _source_file                                    as source_file,
        try_to_timestamp_tz(_extracted_at)              as source_extracted_at
    from source

)

select
    source_record_id,
    order_id,
    customer_id,
    order_date,
    -- Canonical order statuses. Unmapped values surface as 'unknown' and are
    -- rejected by the accepted_values test instead of silently passing.
    case
        when raw_status in ('completed', 'complete') then 'completed'
        when raw_status in ('pending') then 'pending'
        when raw_status in ('cancelled', 'canceled') then 'cancelled'
        else 'unknown'
    end                                                 as order_status,
    raw_status,
    tax_amount,
    source_order_total,
    source_file,
    source_extracted_at
from typed
