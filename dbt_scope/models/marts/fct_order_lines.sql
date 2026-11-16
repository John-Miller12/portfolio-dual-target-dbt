-- One row per order line (design 02, B5). Order attributes are carried on
-- each line, so order counts are COUNT(DISTINCT order_id).
--
-- Amounts are DECIMAL(18, 2). Rounding happens once, on discount_amount,
-- half away from zero (E4); every other amount is exact, so
-- gross = discount + net and net = cost + margin hold on every line.

with order_details as (

    select * from {{ ref('stg_order_details') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

lines as (

    select
        order_details.order_line_id,
        order_details.order_id,
        orders.customer_key,
        order_details.product_id,
        orders.order_date,
        orders.ordered_at,
        order_details.quantity,
        order_details.unit_price,
        order_details.unit_cost,
        order_details.discount_rate,
        (order_details.quantity * order_details.unit_price)::DECIMAL(18, 2)  as gross_amount,
        round(
            order_details.quantity * order_details.unit_price * order_details.discount_rate,
            2
        )::DECIMAL(18, 2)                                                    as discount_amount,
        (order_details.quantity * order_details.unit_cost)::DECIMAL(18, 2)   as cost_amount,
        order_details.is_returned,
        order_details.returned_at,
        order_details.return_reason

    from order_details
    inner join orders
        on order_details.order_id = orders.order_id

),

amounts as (

    select
        *,
        (gross_amount - discount_amount)::DECIMAL(18, 2)  as net_amount

    from lines

)

select
    order_line_id,
    order_id,
    customer_key,
    product_id,
    order_date,
    ordered_at,
    quantity,
    unit_price,
    unit_cost,
    discount_rate,
    gross_amount,
    discount_amount,
    net_amount,
    cost_amount,
    (net_amount - cost_amount)::DECIMAL(18, 2)  as margin_amount,
    is_returned,
    returned_at,
    return_reason,
    (case when is_returned then net_amount else 0 end)::DECIMAL(18, 2)
                                                as returned_net_amount

from amounts
