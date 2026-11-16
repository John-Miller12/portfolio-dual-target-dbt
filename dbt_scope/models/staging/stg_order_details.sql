-- One row per order line. Adds a single-column key (design 02, E3), turns
-- is_returned into a boolean, and replaces the not-returned placeholders
-- (9999-12-31, 00:00:00, 'None') with NULL. Groups the 29 return reasons
-- into six return categories (design 02, B4).

with source as (

    select * from {{ source('retail', 'order_details') }}

),

cleaned as (

    select
        (order_id || '-' || product_id)  as order_line_id,
        order_id::STRING                 as order_id,
        product_id::STRING               as product_id,
        quantity::INTEGER                as quantity,
        unit_cost::DECIMAL(18, 2)        as unit_cost,
        unit_price::DECIMAL(18, 2)       as unit_price,
        discount_rate::DECIMAL(5, 4)     as discount_rate,
        (is_returned = 1)                as is_returned,
        case
            when is_returned = 1
                then (return_date::STRING || ' ' || return_time)::{{ type_timestamp_ntz() }}
        end                              as returned_at,
        case
            when is_returned = 1 then return_reason::STRING
        end                              as return_reason,
        -- No ELSE: an unmapped reason on a returned line is NULL, which fails
        -- assert_return_fields_consistent instead of hiding in an "Other" bucket.
        case
            when is_returned = 1 then
                case
                    when return_reason in (
                        'Wrong Item Sent', 'Wrong Product Sent', 'Wrong Flavor Sent'
                    ) then 'Fulfillment Error'
                    when return_reason in (
                        'Packaging Damage', 'Packaging Defect', 'Broken Package/Leaks',
                        'Crushed Package', 'Crushed/Broken', 'Damaged Can', 'Damaged Seal',
                        'Leaking Bottle', 'Leaking Chemical', 'Damaged Spray Nozzle',
                        'Leaking/Broken Pump', 'Bruised/Damaged'
                    ) then 'Physical Damage'
                    when return_reason in (
                        'Expired Date', 'Spoiled/Expired', 'Molded', 'Molded/Rotten',
                        'Stale/Hard', 'Unpleasant Odor', 'Freezer Burn', 'Thawed/Melted'
                    ) then 'Spoilage'
                    when return_reason in (
                        'Quality Dissatisfaction', 'Taste Defect', 'Strong Odor Issue',
                        'Unripe Product'
                    ) then 'Product Quality'
                    when return_reason = 'Skin Irritation/Allergy' then 'Adverse Reaction'
                    when return_reason = 'Customer Changed Mind' then 'Customer Preference'
                end
        end                              as return_category

    from source

)

select
    *,
    case return_category
        when 'Fulfillment Error'   then 1
        when 'Physical Damage'     then 2
        when 'Spoilage'            then 3
        when 'Product Quality'     then 4
        when 'Adverse Reaction'    then 5
        when 'Customer Preference' then 6
    end  as return_category_order

from cleaned
