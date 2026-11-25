SELECT
    order_item_id,
    order_id,
    product_id,
    quantity,
    unit_price_cents,
    quantity * unit_price_cents AS line_amount_cents
FROM {{ source('core', 'order_items') }}
