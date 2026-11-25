with __dbt__cte__int_ventes_par_produit as (
SELECT
    lignes.product_id,
    sum(lignes.quantity) AS units_sold,
    sum(lignes.line_amount_cents) AS revenue_cents,
    round(sum(lignes.line_amount_cents) / 100.0 / sum(lignes.quantity), 2) AS avg_sale_price_eur
FROM "novamarket"."dbt_dev"."stg_lignes_commande" AS lignes
JOIN "novamarket"."dbt_dev"."stg_commandes" AS commandes
    ON commandes.order_id = lignes.order_id
WHERE commandes.status = 'completed'
GROUP BY lignes.product_id
) SELECT
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
FROM "novamarket"."dbt_dev"."stg_offres" AS offres
JOIN "novamarket"."dbt_dev"."stg_produits" AS produits
    ON produits.product_id = offres.product_id
JOIN "novamarket"."dbt_dev"."stg_categories" AS categories
    ON categories.category_id = produits.category_id
LEFT JOIN __dbt__cte__int_ventes_par_produit AS ventes
    ON ventes.product_id = offres.product_id