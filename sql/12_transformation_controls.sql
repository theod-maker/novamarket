\echo '== Volumes : source, staging, mart =='
SELECT 'fournisseur.offres' AS relation, count(*) AS lignes, sum(available_units) AS unites
FROM fournisseur.offres
UNION ALL
SELECT 'dbt_dev.stg_offres', count(*), sum(available_units) FROM dbt_dev.stg_offres
UNION ALL
SELECT 'dbt_dev.mart_offres_fournisseurs', count(*), sum(available_units)
FROM dbt_dev.mart_offres_fournisseurs;

\echo '== Relations creees par dbt (l intermediate ephemere n apparait pas) =='
SELECT table_name, table_type
FROM information_schema.tables
WHERE table_schema = 'dbt_dev'
ORDER BY table_type, table_name;

\echo '== Jointure directe offres x lignes de commande : la multiplication evitee =='
SELECT count(*) AS lignes_si_jointure_directe
FROM dbt_dev.stg_offres AS offres
JOIN dbt_dev.stg_lignes_commande AS lignes ON lignes.product_id = offres.product_id;

\echo '== Unites vendues des produits offerts : core contre mart =='
SELECT
    (SELECT sum(oi.quantity)
     FROM core.order_items AS oi
     JOIN core.orders AS o ON o.order_id = oi.order_id
     WHERE o.status = 'completed'
       AND oi.product_id IN (SELECT product_id FROM fournisseur.offres)) AS core_unites,
    (SELECT sum(units_sold) FROM dbt_dev.mart_offres_fournisseurs) AS mart_unites;

\echo '== Produits du catalogue sans offre chargee =='
SELECT p.product_id, p.product_name
FROM core.products AS p
LEFT JOIN fournisseur.offres AS o ON o.product_id = p.product_id
WHERE o.offer_id IS NULL
ORDER BY p.product_id;

\echo '== Mart : resume par fournisseur =='
SELECT
    supplier_id,
    count(*) AS offres,
    sum(available_units) AS unites_disponibles,
    sum(offer_value_eur) AS valeur_offres_eur,
    sum(units_sold) AS unites_vendues,
    min(price_gap_eur) AS ecart_min_eur,
    max(price_gap_eur) AS ecart_max_eur
FROM dbt_dev.mart_offres_fournisseurs
GROUP BY supplier_id
ORDER BY supplier_id;

\echo '== Mart : 5 premieres lignes =='
SELECT offer_id, observed_on, supplier_id, product_name, category_name, offer_price_eur,
       available_units, units_sold, avg_sale_price_eur, price_gap_eur
FROM dbt_dev.mart_offres_fournisseurs
ORDER BY offer_id
LIMIT 5;
