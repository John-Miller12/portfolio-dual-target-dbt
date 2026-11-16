-- Design 02, B6: the marts reconcile to raw. Returns one row per failed
-- check, with what was expected and what the marts hold.
--   * Row counts: no lines, customers or products lost or duplicated.
--   * Sums: quantity, gross and cost match the same sums on raw.
--   * Identities: gross = discount + net and net = cost + margin on every
--     line, so the single rounding step (E4) can't leak into other amounts.
-- Values are compared as DECIMAL(38, 2) so the union has one type everywhere.

with raw_lines as (

    select
        count(*)                     as row_count,
        sum(quantity)                as quantity,
        sum(quantity * unit_price)   as gross_amount,
        sum(quantity * unit_cost)    as cost_amount
    from {{ source('retail', 'order_details') }}

),

fact as (

    select
        count(*)                     as row_count,
        sum(quantity)                as quantity,
        sum(gross_amount)            as gross_amount,
        sum(cost_amount)             as cost_amount,
        sum(case when gross_amount != discount_amount + net_amount then 1 else 0 end)
                                     as gross_identity_breaks,
        sum(case when net_amount != cost_amount + margin_amount then 1 else 0 end)
                                     as net_identity_breaks
    from {{ ref('fct_order_lines') }}

),

checks as (

    select 'fct_order_lines row count' as check_name, raw_lines.row_count::DECIMAL(38, 2) as expected, fact.row_count::DECIMAL(38, 2) as actual
    from raw_lines cross join fact

    union all
    select 'sum(quantity)', raw_lines.quantity::DECIMAL(38, 2), fact.quantity::DECIMAL(38, 2)
    from raw_lines cross join fact

    union all
    select 'sum(gross_amount)', raw_lines.gross_amount::DECIMAL(38, 2), fact.gross_amount::DECIMAL(38, 2)
    from raw_lines cross join fact

    union all
    select 'sum(cost_amount)', raw_lines.cost_amount::DECIMAL(38, 2), fact.cost_amount::DECIMAL(38, 2)
    from raw_lines cross join fact

    union all
    select 'lines where gross != discount + net', 0::DECIMAL(38, 2), fact.gross_identity_breaks::DECIMAL(38, 2)
    from fact

    union all
    select 'lines where net != cost + margin', 0::DECIMAL(38, 2), fact.net_identity_breaks::DECIMAL(38, 2)
    from fact

    union all
    select
        'dim_customers row count',
        (select count(*) from {{ source('retail', 'customers') }})::DECIMAL(38, 2),
        (select count(*) from {{ ref('dim_customers') }})::DECIMAL(38, 2)

    union all
    select
        'dim_products row count',
        (select count(*) from {{ ref('products') }})::DECIMAL(38, 2),
        (select count(*) from {{ ref('dim_products') }})::DECIMAL(38, 2)

)

select * from checks
where expected != actual
