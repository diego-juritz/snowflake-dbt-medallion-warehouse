-- Grain: one row per order (order_id).
-- Order-level measures, including tax and payments, live here and only here.
with orders as (

    select * from {{ ref('int_orders_enriched') }}

),

customers as (

    select customer_id, customer_key from {{ ref('dim_customers') }}

),

unknown_customer as (

    select customer_key from {{ ref('dim_customers') }} where is_unknown_member

)

select
    {{ dbt_utils.generate_surrogate_key(['orders.order_id']) }}    as order_key,
    orders.order_id,
    coalesce(customers.customer_key, unknown_customer.customer_key) as customer_key,
    orders.customer_id                                              as source_customer_id,
    orders.has_valid_customer,
    to_number(to_char(orders.order_date, 'YYYYMMDD'))               as order_date_key,
    orders.order_date,
    orders.order_status,
    orders.is_revenue_recognized,
    orders.payment_status,
    orders.item_count,
    orders.total_quantity,
    orders.gross_sales_amount,
    orders.discount_amount,
    orders.net_sales_amount,
    orders.tax_amount,
    orders.order_total_amount,
    orders.amount_captured,
    orders.amount_refunded,
    orders.net_amount_paid,
    -- What is still owed. Not meaningful for cancelled orders, so 0 there.
    iff(orders.order_status = 'cancelled', 0,
        orders.order_total_amount - orders.net_amount_paid)         as outstanding_amount,
    orders.failed_payment_count,
    orders.payment_methods
from orders
left join customers
    on orders.customer_id = customers.customer_id
cross join unknown_customer
