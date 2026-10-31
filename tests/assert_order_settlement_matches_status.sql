-- Scenario assumption (not a universal rule): in this dataset a completed order
-- is fully settled and a cancelled order keeps no money. A business that allows
-- invoicing (pay later) or partial cancellation would need a different rule.
select
    order_id,
    order_status,
    order_total_amount,
    net_amount_paid
from {{ ref('fct_orders') }}
where (order_status = 'completed' and net_amount_paid <> order_total_amount)
   or (order_status = 'cancelled' and net_amount_paid <> 0)
