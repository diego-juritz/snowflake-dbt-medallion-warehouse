with source as (

    select * from {{ source('bronze', 'raw_order_items') }}

),

typed as (

    select
        try_to_number(_record_id)                       as source_record_id,
        upper(trim(order_item_id))                      as order_item_id,
        upper(trim(order_id))                           as order_id,
        upper(trim(product_id))                         as product_id,
        try_to_number(trim(quantity))                   as quantity,
        -- Price charged on this line (may differ from the current list price).
        try_to_number(trim(unit_price), 12, 2)          as unit_price,
        coalesce(try_to_number(nullif(trim(discount_amount), ''), 12, 2), 0) as discount_amount,
        _source_file                                    as source_file
    from source

)

select
    source_record_id,
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    discount_amount,
    -- Business definitions (docs/design_decisions.md#metric-definitions):
    --   gross sales = quantity * unit price, before discounts and tax
    --   net sales   = gross sales - discounts, excluding tax
    quantity * unit_price                               as gross_sales_amount,
    quantity * unit_price - discount_amount             as net_sales_amount,
    source_file
from typed
