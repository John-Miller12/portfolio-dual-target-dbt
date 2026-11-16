-- One row per order. customer_id is replaced by its pseudonym (02A, G1).
-- order_time is loaded as text (design 01, D8) and folded into ordered_at.

with source as (

    select * from {{ source('retail', 'orders') }}

)

select
    order_id::STRING                   as order_id,
    {{ pseudonymize('customer_id') }}  as customer_key,
    order_date::DATE                   as order_date,
    (order_date::STRING || ' ' || order_time)::{{ type_timestamp_ntz() }} as ordered_at

from source
