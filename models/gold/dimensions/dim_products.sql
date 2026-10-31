-- Grain: one row per product.
select
    {{ dbt_utils.generate_surrogate_key(['product_id']) }}  as product_key,
    product_id,
    product_name,
    coalesce(category, 'Uncategorized')                     as category,
    list_price,
    is_active
from {{ ref('stg_products') }}
