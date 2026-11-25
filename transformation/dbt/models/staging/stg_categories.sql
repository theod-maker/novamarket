SELECT
    category_id,
    trim(category_name) AS category_name,
    parent_category_id
FROM {{ source('core', 'categories') }}
