-- Grain guard: summing line-level net sales in fct_order_items must reproduce
-- fct_orders exactly, per order and in total. A difference indicates fan-out
-- (duplicated lines) or dropped lines between the two facts.
with lines as (

    select order_id, sum(net_sales_amount) as line_net_sales, count(*) as line_count
    from {{ ref('fct_order_items') }}
    group by order_id

)

select
    orders.order_id,
    orders.net_sales_amount,
    lines.line_net_sales,
    orders.item_count,
    lines.line_count
from {{ ref('fct_orders') }} as orders
full outer join lines
    on orders.order_id = lines.order_id
where orders.order_id is null
   or lines.order_id is null
   or orders.net_sales_amount <> lines.line_net_sales
   or orders.item_count <> lines.line_count
