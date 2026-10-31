-- Rule: net payments can never exceed the order value, and refunds can never
-- exceed captured money. Either condition would indicate duplicated payment
-- events or payments joined at the wrong grain.
select
    order_id,
    order_total_amount,
    amount_captured,
    amount_refunded,
    net_amount_paid
from {{ ref('fct_orders') }}
where net_amount_paid > order_total_amount
   or amount_refunded > amount_captured
