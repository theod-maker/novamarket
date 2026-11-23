\echo ''
\echo '== H1. Arbre des categories (WITH RECURSIVE), avec controle des cycles'
\echo '   Grain de sortie : une ligne par categorie atteinte depuis une racine.'
WITH RECURSIVE category_tree AS (
    SELECT
        category_id,
        category_name,
        parent_category_id,
        category_id AS root_category_id,
        0 AS depth,
        ARRAY[category_id] AS path_ids,
        category_name::text AS path_names
    FROM core.categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT
        c.category_id,
        c.category_name,
        c.parent_category_id,
        t.root_category_id,
        t.depth + 1,
        t.path_ids || c.category_id,
        t.path_names || ' > ' || c.category_name
    FROM core.categories AS c
    JOIN category_tree AS t ON c.parent_category_id = t.category_id
    WHERE NOT c.category_id = ANY (t.path_ids)
        AND t.depth < 10
)
SELECT category_id, depth, path_names
FROM category_tree
ORDER BY path_names;

\echo ''
\echo '== H2. Controle des rattachements : categories non atteintes depuis une racine'
WITH RECURSIVE category_tree AS (
    SELECT category_id, ARRAY[category_id] AS path_ids, 0 AS depth
    FROM core.categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, t.path_ids || c.category_id, t.depth + 1
    FROM core.categories AS c
    JOIN category_tree AS t ON c.parent_category_id = t.category_id
    WHERE NOT c.category_id = ANY (t.path_ids)
        AND t.depth < 10
)
SELECT
    (SELECT COUNT(*) FROM core.categories) AS categories_in_catalog,
    (SELECT COUNT(DISTINCT category_id) FROM category_tree) AS categories_reached,
    (SELECT COUNT(*) FROM category_tree) AS tree_rows,
    (SELECT MAX(depth) FROM category_tree) AS max_depth;

\echo ''
\echo '== H3. Chiffre d affaires consolide par famille (categorie racine)'
\echo '   Grain de sortie : une ligne par categorie racine. Perimetre : status = completed.'
WITH RECURSIVE category_tree AS (
    SELECT category_id, category_id AS root_category_id, ARRAY[category_id] AS path_ids, 0 AS depth
    FROM core.categories
    WHERE parent_category_id IS NULL
    UNION ALL
    SELECT c.category_id, t.root_category_id, t.path_ids || c.category_id, t.depth + 1
    FROM core.categories AS c
    JOIN category_tree AS t ON c.parent_category_id = t.category_id
    WHERE NOT c.category_id = ANY (t.path_ids)
        AND t.depth < 10
),
product_revenue AS (
    SELECT i.product_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    WHERE o.status = 'completed'
    GROUP BY i.product_id
)
SELECT
    r.category_name AS family,
    COUNT(DISTINCT p.product_id) AS products,
    ROUND(SUM(pr.revenue_cents) / 100.0, 2) AS revenue_eur,
    ROUND(100.0 * SUM(pr.revenue_cents) / SUM(SUM(pr.revenue_cents)) OVER (), 1) AS share_pct
FROM product_revenue AS pr
JOIN core.products AS p ON p.product_id = pr.product_id
JOIN category_tree AS t ON t.category_id = p.category_id
JOIN core.categories AS r ON r.category_id = t.root_category_id
GROUP BY r.category_name
ORDER BY revenue_eur DESC;

\echo ''
\echo '== H4. Chiffre d affaires par niveau de l arbre : risque de double comptage'
\echo '   Chaque produit est compte une fois a sa categorie et une fois a chaque ancetre.'
WITH RECURSIVE ancestors AS (
    SELECT category_id AS leaf_category_id, category_id AS ancestor_id, 0 AS distance
    FROM core.categories
    UNION ALL
    SELECT a.leaf_category_id, c.parent_category_id, a.distance + 1
    FROM ancestors AS a
    JOIN core.categories AS c ON c.category_id = a.ancestor_id
    WHERE c.parent_category_id IS NOT NULL
        AND a.distance < 10
),
product_revenue AS (
    SELECT i.product_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    WHERE o.status = 'completed'
    GROUP BY i.product_id
),
revenue_by_category AS (
    SELECT a.ancestor_id AS category_id, SUM(pr.revenue_cents) AS revenue_cents
    FROM product_revenue AS pr
    JOIN core.products AS p ON p.product_id = pr.product_id
    JOIN ancestors AS a ON a.leaf_category_id = p.category_id
    GROUP BY a.ancestor_id
)
SELECT
    c.category_id,
    c.category_name,
    c.parent_category_id,
    ROUND(rc.revenue_cents / 100.0, 2) AS revenue_including_subcategories_eur
FROM revenue_by_category AS rc
JOIN core.categories AS c ON c.category_id = rc.category_id
ORDER BY c.parent_category_id NULLS FIRST, c.category_id;

\echo ''
\echo '== H4 bis. Somme de toutes les lignes de H4 comparee au vrai total'
WITH RECURSIVE ancestors AS (
    SELECT category_id AS leaf_category_id, category_id AS ancestor_id, 0 AS distance
    FROM core.categories
    UNION ALL
    SELECT a.leaf_category_id, c.parent_category_id, a.distance + 1
    FROM ancestors AS a
    JOIN core.categories AS c ON c.category_id = a.ancestor_id
    WHERE c.parent_category_id IS NOT NULL
        AND a.distance < 10
),
lines AS (
    SELECT i.quantity * i.unit_price_cents AS line_cents, p.category_id
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    JOIN core.products AS p ON p.product_id = i.product_id
    WHERE o.status = 'completed'
)
SELECT
    ROUND((SELECT SUM(line_cents) FROM lines) / 100.0, 2) AS true_total_eur,
    ROUND((SELECT SUM(l.line_cents) FROM lines AS l
        JOIN ancestors AS a ON a.leaf_category_id = l.category_id) / 100.0, 2)
        AS sum_over_all_levels_eur;
