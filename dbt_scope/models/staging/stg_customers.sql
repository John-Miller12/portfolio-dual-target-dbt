-- One row per customer. The raw customer_id, exact age and city are
-- deliberately not selected: customer_key is a salted pseudonym (02A, G1),
-- age is reduced to a marketing band (design 02, B4; 02A, G7), and city is
-- too precise next to region (02A, G10).

with source as (

    select * from {{ source('retail', 'customers') }}

)

select
    {{ pseudonymize('customer_id') }}  as customer_key,
    gender::STRING                     as gender,
    case
        when age between 18 and 24 then '18-24'
        when age between 25 and 34 then '25-34'
        when age between 35 and 44 then '35-44'
        when age between 45 and 54 then '45-54'
        when age between 55 and 64 then '55-64'
        when age >= 65             then '65+'
    end                                as age_band,
    region::STRING                     as region,
    customer_segment::STRING           as customer_segment,
    sign_up_date::DATE                 as sign_up_date

from source
