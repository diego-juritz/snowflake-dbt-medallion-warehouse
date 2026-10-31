-- Grain: one row per order line (order_item_id).
-- Line-level measures only. Tax and payments are order-level facts and are
-- deliberately NOT allocated to lines; use fct_orders for them.
with items as (

    select * from {{ ref('stg_order_items') }}

),

orders as (

    select order_id, order_key, customer_key, order_date_key, order_status, is_revenue_recognized
    from {{ ref('fct_orders') }}

),

products as (

    select product_id, product_key from {{ ref('dim_products') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['items.order_item_id']) }}    as order_item_key,
    items.order_item_id,
    orders.order_key,
    items.order_id,
    orders.customer_key,
    products.product_key,
    orders.order_date_key,
    orders.order_status,
    orders.is_revenue_recognized,
    items.quantity,
    items.unit_price,
    items.gross_sales_amount,
    items.discount_amount,
    items.net_sales_amount
from items
inner join orders
    on items.order_id = orders.order_id
left join products
    on items.product_id = products.product_id
