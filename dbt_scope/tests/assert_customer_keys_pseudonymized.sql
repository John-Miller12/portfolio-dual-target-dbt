-- 02A section 8: no raw customer IDs past raw, and no hash collisions.
-- Returns a row (failure) if any key looks like a raw ID or isn't a
-- 64-character digest, or if hashing merged distinct customers.

with keys as (

    select customer_key, 'stg_customers' as model from {{ ref('stg_customers') }}
    union all
    select customer_key, 'stg_orders' as model from {{ ref('stg_orders') }}
    union all
    select customer_key, 'dim_customers' as model from {{ ref('dim_customers') }}
    union all
    select customer_key, 'fct_order_lines' as model from {{ ref('fct_order_lines') }}

),

bad_keys as (

    select model, customer_key, 'not pseudonymized' as reason
    from keys
    where customer_key like 'CSTMR%'
       or length(customer_key) != 64

),

collisions as (

    select
        model,
        count(distinct customer_key)::STRING as customer_key,
        'distinct keys != distinct raw ids' as reason
    from keys
    where model in ('stg_customers', 'dim_customers')
    group by model
    having count(distinct customer_key) != (
        select count(distinct customer_id) from {{ source('retail', 'customers') }}
    )

)

select * from bad_keys
union all
select * from collisions
