SELECT
    product_id,
    sku,
    trim(product_name) AS product_name,
    category_id,
    first_listed_on
FROM {{ source('core', 'products') }}
