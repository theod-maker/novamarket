SELECT
    order_id,
    customer_id,
    ordered_on,
    status
FROM {{ source('core', 'orders') }}
