-- Grain: one row per order_id that has at least one payment event.
--
-- Payments are aggregated to the order grain BEFORE any join with order items.
-- Joining raw payments to order lines would multiply each payment by the number
-- of lines (fan-out) and overstate amounts.
--
-- Payment status rules:
--   success  -> money captured
--   refunded -> captured money returned (amount is the refunded value, positive)
--   failed   -> declined attempt; never counts as paid
--   pending  -> authorised but not captured; not counted as paid
with payments as (

    select * from {{ ref('stg_payments') }}

)

select
    order_id,
    count(*)                                                            as payment_event_count,
    sum(iff(payment_status = 'success', amount, 0))                     as amount_captured,
    sum(iff(payment_status = 'refunded', amount, 0))                    as amount_refunded,
    sum(iff(payment_status = 'pending', amount, 0))                     as amount_pending,
    sum(iff(payment_status = 'failed', amount, 0))                      as amount_failed,
    sum(iff(payment_status = 'success', amount, 0))
        - sum(iff(payment_status = 'refunded', amount, 0))              as net_amount_paid,
    count_if(payment_status = 'failed')                                 as failed_payment_count,
    listagg(distinct payment_method, ',') within group (order by payment_method) as payment_methods,
    min(payment_date)                                                   as first_payment_date,
    max(payment_date)                                                   as last_payment_date
from payments
group by order_id
