with source as (

    select * from {{ source('bronze', 'raw_payments') }}

)

select
    try_to_number(_record_id)                               as source_record_id,
    upper(trim(payment_id))                                 as payment_id,
    upper(trim(order_id))                                   as order_id,
    -- 'Credit Card', 'CREDIT_CARD', 'credit_card' -> 'credit_card'
    replace(lower(trim(payment_method)), ' ', '_')          as payment_method,
    lower(trim(payment_status))                             as payment_status,
    try_to_number(trim(amount), 12, 2)                      as amount,
    try_to_date(trim(payment_date), 'YYYY-MM-DD')           as payment_date,
    _source_file                                            as source_file
from source
