with source as (

    select * from {{ source('bronze', 'raw_products') }}

)

select
    try_to_number(_record_id)                           as source_record_id,
    upper(trim(product_id))                             as product_id,
    trim(product_name)                                  as product_name,
    -- Category casing varies in the source; a missing category stays NULL here
    -- and is labelled 'Uncategorized' in dim_products.
    initcap(nullif(trim(category), ''))                 as category,
    try_to_number(trim(unit_price), 12, 2)              as list_price,
    try_to_boolean(trim(is_active))                     as is_active,
    _source_file                                        as source_file,
    try_to_timestamp_tz(_extracted_at)                  as source_extracted_at
from source
