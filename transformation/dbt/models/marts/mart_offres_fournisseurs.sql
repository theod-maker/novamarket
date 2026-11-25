SELECT
    offres.offer_id,
    offres.observed_on,
    offres.supplier_id,
    offres.product_id,
    produits.product_name,
    categories.category_name,
    offres.price_eur AS offer_price_eur,
    offres.available_units,
    round(offres.price_eur * offres.available_units, 2) AS offer_value_eur,
    coalesce(ventes.units_sold, 0) AS units_sold,
    ventes.avg_sale_price_eur,
    ventes.avg_sale_price_eur - offres.price_eur AS price_gap_eur
FROM {{ ref('stg_offres') }} AS offres
JOIN {{ ref('stg_produits') }} AS produits
    ON produits.product_id = offres.product_id
JOIN {{ ref('stg_categories') }} AS categories
    ON categories.category_id = produits.category_id
LEFT JOIN {{ ref('int_ventes_par_produit') }} AS ventes
    ON ventes.product_id = offres.product_id
