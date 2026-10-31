-- Grain: one row per (order_id, exception_type).
--
-- Exception register for order-level data-quality issues. Records are flagged
-- here, NOT removed from the pipeline, so they stay visible and auditable.
-- Gold decides how each flag is treated (e.g. orphan orders map to the
-- "Unknown customer" member of dim_customers).
with orders as (

    select * from {{ ref('int_orders_enriched') }}

),

exceptions as (

    select order_id, 'orphan_customer' as exception_type,
           'customer_id ' || customer_id || ' not found in customers' as detail
    from orders where not has_valid_customer

    union all

    select order_id, 'unparseable_order_date', 'order_date could not be parsed'
    from orders where order_date is null

    union all

    select order_id, 'unknown_order_status', 'status not in the canonical mapping'
    from orders where order_status = 'unknown'

    union all

    select order_id, 'order_without_items', 'order has no order lines'
    from orders where item_count = 0

    union all

    select order_id, 'total_mismatch',
           'source total ' || source_order_total || ' != items + tax ' || order_total_amount
    from orders where source_order_total <> order_total_amount

)

select
    exceptions.order_id,
    exceptions.exception_type,
    exceptions.detail
from exceptions
