-- One row per customer. The raw customer_id and exact age are deliberately
-- not selected: customer_key is a salted pseudonym (02A, G1) and age is
-- reduced to a marketing band (design 02, B4; 02A, G7).

with source as (

    select * from {{ source('retail', 'customers') }}

)

select
    {{ pseudonymize('customer_id') }}  as customer_key,
    cast(gender as string)             as gender,
    case
        when age between 18 and 24 then '18-24'
        when age between 25 and 34 then '25-34'
        when age between 35 and 44 then '35-44'
        when age between 45 and 54 then '45-54'
        when age between 55 and 64 then '55-64'
        when age >= 65             then '65+'
    end                                as age_band,
    case
        when age between 18 and 24 then 1
        when age between 25 and 34 then 2
        when age between 35 and 44 then 3
        when age between 45 and 54 then 4
        when age between 55 and 64 then 5
        when age >= 65             then 6
    end                                as age_band_order,
    cast(city as string)               as city,
    cast(region as string)             as region,
    cast(customer_segment as string)   as customer_segment,
    cast(sign_up_date as date)         as sign_up_date

from source
