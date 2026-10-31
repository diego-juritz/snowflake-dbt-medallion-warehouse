-- Business questions answered from the Gold star schema.
-- Compile with `dbt compile --select business_questions`, then run the
-- statements in target/compiled/.../analyses/business_questions.sql.
-- Metric definitions: docs/design_decisions.md#metric-definitions
-- Expected results:   examples/expected_query_results.md

-- Q1. Monthly gross and net sales (completed orders only).
select
    d.year_month,
    count(*)                                        as completed_orders,
    sum(o.gross_sales_amount)                       as gross_sales,
    sum(o.discount_amount)                          as discounts,
    sum(o.net_sales_amount)                         as net_sales
from {{ ref('fct_orders') }} as o
inner join {{ ref('dim_date') }} as d
    on o.order_date_key = d.date_key
where o.is_revenue_recognized
group by d.year_month
order by d.year_month;

-- Q2. Top 5 products by net sales (completed orders only).
select
    p.product_id,
    p.product_name,
    p.category,
    sum(i.quantity)                                 as units_sold,
    sum(i.net_sales_amount)                         as net_sales
from {{ ref('fct_order_items') }} as i
inner join {{ ref('dim_products') }} as p
    on i.product_key = p.product_key
where i.is_revenue_recognized
group by p.product_id, p.product_name, p.category
order by net_sales desc, p.product_id
limit 5;

-- Q3. Top 5 customers by net sales (orphan orders appear as "Unknown customer").
select
    c.customer_id,
    c.full_name,
    count(*)                                        as completed_orders,
    sum(o.net_sales_amount)                         as net_sales
from {{ ref('fct_orders') }} as o
inner join {{ ref('dim_customers') }} as c
    on o.customer_key = c.customer_key
where o.is_revenue_recognized
group by c.customer_id, c.full_name
order by net_sales desc, c.customer_id
limit 5;

-- Q4. Average order value = net sales / completed orders (excludes tax).
select
    count(*)                                        as completed_orders,
    sum(net_sales_amount)                           as net_sales,
    round(sum(net_sales_amount) / nullif(count(*), 0), 2) as average_order_value
from {{ ref('fct_orders') }}
where is_revenue_recognized;

-- Q5. Orders by status, with value at stake.
select
    order_status,
    count(*)                                        as orders,
    sum(order_total_amount)                         as order_value_incl_tax,
    sum(net_amount_paid)                            as net_amount_paid,
    sum(outstanding_amount)                         as outstanding_amount
from {{ ref('fct_orders') }}
group by order_status
order by order_status;

-- Q6. Net sales by product category and month (completed orders only).
select
    d.year_month,
    p.category,
    sum(i.net_sales_amount)                         as net_sales
from {{ ref('fct_order_items') }} as i
inner join {{ ref('dim_products') }} as p on i.product_key = p.product_key
inner join {{ ref('dim_date') }} as d on i.order_date_key = d.date_key
where i.is_revenue_recognized
group by d.year_month, p.category
order by d.year_month, p.category;

-- Q7. Data-quality summary: what the pipeline flagged and how it was handled.
select 'raw customer records'               as check_name, count(*) as value from {{ ref('stg_customers') }}
union all
select 'distinct customers after dedup',     count(*) from {{ ref('int_customers_deduplicated') }}
union all
select 'orders with unknown customer',      count(*) from {{ ref('fct_orders') }} where not has_valid_customer
union all
select 'orders with a failed payment attempt', count(*) from {{ ref('fct_orders') }} where failed_payment_count > 0
union all
select 'cancelled orders refunded',          count(*) from {{ ref('fct_orders') }} where order_status = 'cancelled' and amount_refunded > 0
union all
select 'open exceptions',                    count(*) from {{ ref('int_order_exceptions') }};
