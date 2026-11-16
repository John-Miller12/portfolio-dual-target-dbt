-- Design 02, B6: return fields are populated exactly when a line was
-- returned, and no placeholder survives staging. Every returned line's
-- reason maps to a return category (that CASE has no ELSE, so an unmapped
-- reason shows up here as a NULL category). Returns failing lines.

select
    order_line_id,
    is_returned,
    returned_at,
    return_reason,
    return_category
from {{ ref('stg_order_details') }}
where
    (
        is_returned
        and (
            returned_at is null
            or return_reason is null
            or return_category is null
            or return_category_order is null
            or extract(year from returned_at) = 9999
            or return_reason = 'None'
        )
    )
    or (
        not is_returned
        and (
            returned_at is not null
            or return_reason is not null
            or return_category is not null
        )
    )
