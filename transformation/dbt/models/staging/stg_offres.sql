SELECT
    offer_id,
    observed_on,
    supplier_id,
    product_id,
    price_cents,
    round(price_cents / 100.0, 2) AS price_eur,
    available_units
FROM {{ source('fournisseur', 'offres') }}
