-- One row per calendar day (design 02, R5). Only date_day is stored: grains
-- are computed with DATE_TRUNC, never week-number functions, which differ
-- on Snowflake (design 02, A4 note).
--
-- dbt.date_spine ships with dbt itself (no package, E5) and is dispatched
-- per adapter. The range covers whole calendar years around the data:
-- sign-ups from 2020, orders and returns through mid-2026. The
-- relationships test from fct_order_lines.order_date guards the range.
-- end_date is EXCLUSIVE: date_spine makes datediff(start, end) rows, so the
-- last day built is 2026-12-31.

with spine as (

    {{ dbt.date_spine(
        datepart="day",
        start_date="'2020-01-01'::DATE",
        end_date="'2027-01-01'::DATE"
    ) }}

)

select date_day::DATE as date_day

from spine
