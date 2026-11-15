-- One row per product. Seed columns are UPPER_SNAKE and selected unquoted,
-- so they resolve on every target (design 01, D7).

with source as (

    select * from {{ ref('products') }}

)

select
    cast(product_id as string)    as product_id,
    cast(product_name as string)  as product_name,
    cast(category_id as string)   as category_id

from source
