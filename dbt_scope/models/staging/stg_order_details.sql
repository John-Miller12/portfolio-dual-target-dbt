-- One row per order line. Adds a single-column key (design 02, E3), turns
-- is_returned into a boolean, and replaces the not-returned placeholders
-- (9999-12-31, 00:00:00, 'None') with NULL.

with source as (

    select * from {{ source('retail', 'order_details') }}

)

select
    (order_id || '-' || product_id)  as order_line_id,
    order_id::STRING                 as order_id,
    product_id::STRING               as product_id,
    quantity::INTEGER                as quantity,
    unit_cost::DECIMAL(18, 2)        as unit_cost,
    unit_price::DECIMAL(18, 2)       as unit_price,
    discount_rate::DECIMAL(5, 4)     as discount_rate,
    (is_returned = 1)                as is_returned,
    case
        when is_returned = 1
            then (return_date::STRING || ' ' || return_time)::{{ type_timestamp_ntz() }}
    end                              as returned_at,
    case
        when is_returned = 1 then return_reason::STRING
    end                              as return_reason

from source
