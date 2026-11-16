-- One row per product category.

with source as (

    select * from {{ ref('categories') }}

)

select
    category_id::STRING    as category_id,
    category_name::STRING  as category_name

from source
