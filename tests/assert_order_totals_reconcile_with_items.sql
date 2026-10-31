-- Rule: the order total stated by the source must equal the sum of its lines'
-- net sales plus the order tax. A mismatch means missing/duplicated lines or a
-- pricing error upstream. Returns offending orders.
select
    order_id,
    source_order_total,
    order_total_amount as recomputed_order_total
from {{ ref('int_orders_enriched') }}
where source_order_total <> order_total_amount
