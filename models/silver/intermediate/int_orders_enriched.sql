-- Grain: one row per order_id. Combines the order header with line-level and
-- payment-level aggregates, each pre-aggregated to the order grain so that no
-- join can fan out.
with orders as (

    select * from {{ ref('stg_orders') }}

),

items as (

    select
        order_id,
        count(*)                    as item_count,
        sum(quantity)               as total_quantity,
        sum(gross_sales_amount)     as gross_sales_amount,
        sum(discount_amount)        as discount_amount,
        sum(net_sales_amount)       as net_sales_amount
    from {{ ref('stg_order_items') }}
    group by order_id

),

payments as (

    select * from {{ ref('int_payments_by_order') }}

),

customers as (

    select customer_id from {{ ref('int_customers_deduplicated') }}

)

select
    orders.order_id,
    orders.customer_id,
    customers.customer_id is not null                       as has_valid_customer,
    orders.order_date,
    orders.order_status,
    -- Only completed orders count toward sales metrics.
    orders.order_status = 'completed'                       as is_revenue_recognized,
    coalesce(items.item_count, 0)                           as item_count,
    coalesce(items.total_quantity, 0)                       as total_quantity,
    coalesce(items.gross_sales_amount, 0)                   as gross_sales_amount,
    coalesce(items.discount_amount, 0)                      as discount_amount,
    coalesce(items.net_sales_amount, 0)                     as net_sales_amount,
    orders.tax_amount,
    -- Order value = net sales + tax: what the customer is asked to pay.
    coalesce(items.net_sales_amount, 0) + orders.tax_amount as order_total_amount,
    orders.source_order_total,
    coalesce(payments.payment_event_count, 0)               as payment_event_count,
    coalesce(payments.amount_captured, 0)                   as amount_captured,
    coalesce(payments.amount_refunded, 0)                   as amount_refunded,
    coalesce(payments.amount_pending, 0)                    as amount_pending,
    coalesce(payments.net_amount_paid, 0)                   as net_amount_paid,
    coalesce(payments.failed_payment_count, 0)              as failed_payment_count,
    payments.payment_methods,
    case
        when coalesce(payments.amount_refunded, 0) > 0
             and coalesce(payments.net_amount_paid, 0) = 0             then 'refunded'
        when coalesce(payments.net_amount_paid, 0)
             >= coalesce(items.net_sales_amount, 0) + orders.tax_amount then 'paid'
        when coalesce(payments.net_amount_paid, 0) > 0                 then 'partially_paid'
        when coalesce(payments.amount_pending, 0) > 0                  then 'payment_pending'
        else 'unpaid'
    end                                                     as payment_status
from orders
left join items     on orders.order_id = items.order_id
left join payments  on orders.order_id = payments.order_id
left join customers on orders.customer_id = customers.customer_id
