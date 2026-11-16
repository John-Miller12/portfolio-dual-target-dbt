-- One row per product. Seed columns are UPPER_SNAKE and selected unquoted,
-- so they resolve on every target (design 01, D7).

with source as (

    select * from {{ ref('products') }}

)

select
    product_id::STRING    as product_id,
    product_name::STRING  as product_name,
    category_id::STRING   as category_id

from source
