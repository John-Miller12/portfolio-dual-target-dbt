-- One row per order. customer_id is replaced by its pseudonym (02A, G1).
-- order_time is loaded as text (design 01, D8) and folded into ordered_at.

with source as (

    select * from {{ source('retail', 'orders') }}

)

select
    cast(order_id as string)                    as order_id,
    {{ pseudonymize('customer_id') }}           as customer_key,
    cast(order_date as date)                    as order_date,
    cast(
        cast(order_date as string) || ' ' || order_time
        as {{ type_timestamp_ntz() }}
    )                                           as ordered_at

from source
