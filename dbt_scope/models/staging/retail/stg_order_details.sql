-- One row per order line. Adds a single-column key (design 02, E3), turns
-- is_returned into a boolean, and replaces the not-returned placeholders
-- (9999-12-31, 00:00:00, 'None') with NULL.

with source as (

    select * from {{ source('retail', 'order_details') }}

)

select
    order_id || '-' || product_id               as order_line_id,
    cast(order_id as string)                    as order_id,
    cast(product_id as string)                  as product_id,
    cast(quantity as integer)                   as quantity,
    cast(unit_cost as decimal(18, 2))           as unit_cost,
    cast(unit_price as decimal(18, 2))          as unit_price,
    cast(discount_rate as decimal(5, 4))        as discount_rate,
    is_returned = 1                             as is_returned,
    case
        when is_returned = 1 then cast(
            cast(return_date as string) || ' ' || return_time
            as {{ type_timestamp_ntz() }}
        )
    end                                         as returned_at,
    case
        when is_returned = 1 then cast(return_reason as string)
    end                                         as return_reason

from source
