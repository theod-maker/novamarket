\echo ''
\echo '== C1. Volumes recus, integres et rejetes du catalogue'
SELECT
    source_file,
    received_rows,
    integrated_rows,
    rejected_rows,
    received_rows - integrated_rows - rejected_rows AS gap_must_be_zero
FROM (
    SELECT
        'categories.csv' AS source_file,
        (SELECT COUNT(*) FROM reception.categories) AS received_rows,
        (SELECT COUNT(*) FROM core.categories) AS integrated_rows,
        (SELECT COUNT(DISTINCT source_row) FROM quality.rejected_rows
            WHERE source_file = 'categories.csv') AS rejected_rows
    UNION ALL
    SELECT
        'products.csv',
        (SELECT COUNT(*) FROM reception.products),
        (SELECT COUNT(*) FROM core.products),
        (SELECT COUNT(DISTINCT source_row) FROM quality.rejected_rows
            WHERE source_file = 'products.csv')
) AS volumes;

\echo ''
\echo '== C2. Rejets du catalogue'
SELECT q.source_file, q.source_row, q.source_key, q.reason, r.sku, r.product_name
FROM quality.rejected_rows AS q
LEFT JOIN reception.products AS r
    ON q.source_file = 'products.csv' AND r.source_row = q.source_row
WHERE q.source_file IN ('categories.csv', 'products.csv')
ORDER BY q.source_file, q.source_row;

\echo ''
\echo '== C3. Le doublon de produit est-il identique a la premiere fiche ?'
SELECT
    product_id,
    COUNT(*) AS source_rows,
    COUNT(DISTINCT (sku, product_name, category_id, first_listed_on)) AS distinct_versions
FROM reception.products
GROUP BY product_id
HAVING COUNT(*) > 1;

\echo ''
\echo '== C4. Couverture des codes produit : lignes de commande sans fiche produit'
SELECT COUNT(*) AS order_items_without_product
FROM core.order_items AS i
WHERE NOT EXISTS (SELECT 1 FROM core.products AS p WHERE p.product_id = i.product_id);

\echo ''
\echo '== C4 bis. Produits du catalogue jamais vendus'
SELECT p.product_id, p.product_name
FROM core.products AS p
WHERE NOT EXISTS (SELECT 1 FROM core.order_items AS i WHERE i.product_id = p.product_id);

\echo ''
\echo '== C5. Produits rattaches a une categorie qui a des sous-categories'
SELECT p.product_id, p.category_id
FROM core.products AS p
WHERE EXISTS (
    SELECT 1 FROM core.categories AS c WHERE c.parent_category_id = p.category_id
);

\echo ''
\echo '== C6. Coherence des dates : ventes avant la date declaree de mise en vente'
SELECT
    p.product_id,
    p.first_listed_on,
    MIN(o.ordered_on) AS first_order_date,
    COUNT(*) AS lines_before_listing,
    COUNT(DISTINCT o.order_id) AS orders_before_listing,
    COUNT(*) FILTER (WHERE o.status = 'completed') AS completed_lines_before_listing
FROM core.order_items AS i
JOIN core.orders AS o ON o.order_id = i.order_id
JOIN core.products AS p ON p.product_id = i.product_id
WHERE o.ordered_on < p.first_listed_on
GROUP BY p.product_id, p.first_listed_on
ORDER BY p.product_id;

\echo ''
\echo '== C7. Contrainte ajoutee sur les lignes de commande'
SELECT conname AS constraint_name, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'core.order_items'::regclass AND contype = 'f'
ORDER BY conname;
