SELECT
    lignes.product_id,
    sum(lignes.quantity) AS units_sold,
    sum(lignes.line_amount_cents) AS revenue_cents,
    round(sum(lignes.line_amount_cents) / 100.0 / sum(lignes.quantity), 2) AS avg_sale_price_eur
FROM {{ ref('stg_lignes_commande') }} AS lignes
JOIN {{ ref('stg_commandes') }} AS commandes
    ON commandes.order_id = lignes.order_id
WHERE commandes.status = 'completed'
GROUP BY lignes.product_id
