WITH core_ventes AS (
    SELECT sum(lignes.quantity * lignes.unit_price_cents) AS total_cents
    FROM {{ source('core', 'order_items') }} AS lignes
    join {{ source('core', 'orders') }} AS commandes
        ON commandes.order_id = lignes.order_id
    WHERE commandes.status = 'completed'
),

dbt_ventes AS (
    SELECT sum(revenue_cents) AS total_cents
    FROM {{ ref('int_ventes_par_produit') }}
)

SELECT core_ventes.total_cents, dbt_ventes.total_cents
FROM core_ventes
CROSS JOIN dbt_ventes
WHERE core_ventes.total_cents <> dbt_ventes.total_cents
