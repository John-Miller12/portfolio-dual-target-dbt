-- One row per product, with its category folded in (design 02, E2).

with products as (

    select * from {{ ref('stg_products') }}

),

categories as (

    select * from {{ ref('stg_categories') }}

)

select
    products.product_id,
    products.product_name,
    products.category_id,
    categories.category_name

from products
inner join categories
    on products.category_id = categories.category_id
