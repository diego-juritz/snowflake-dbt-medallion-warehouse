-- Metric invariant: recognized net sales in Gold equal the same metric computed
-- independently from Silver line items and order statuses. Protects against
-- double counting or rows dropped by Gold joins (e.g. the orphan order).
with silver as (

    select sum(items.net_sales_amount) as net_sales
    from {{ ref('stg_order_items') }} as items
    inner join {{ ref('stg_orders') }} as orders
        on items.order_id = orders.order_id
    where orders.order_status = 'completed'

),

gold as (

    select sum(net_sales_amount) as net_sales
    from {{ ref('fct_orders') }}
    where is_revenue_recognized

)

select silver.net_sales as silver_net_sales, gold.net_sales as gold_net_sales
from silver
cross join gold
where silver.net_sales <> gold.net_sales
   or gold.net_sales is null
