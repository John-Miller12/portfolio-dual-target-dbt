-- One row per product category.

with source as (

    select * from {{ ref('categories') }}

)

select
    cast(category_id as string)    as category_id,
    cast(category_name as string)  as category_name

from source
