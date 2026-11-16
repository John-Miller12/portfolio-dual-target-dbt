-- One row per customer, keyed by the pseudonym (02A, G1). No raw ID or
-- exact age exists upstream, so none can reach this table.

with customers as (

    select * from {{ ref('stg_customers') }}

)

select
    customer_key,
    gender,
    age_band,
    age_band_order,
    city,
    region,
    customer_segment,
    sign_up_date

from customers
