\echo ''
\echo '== R1. Classement des produits par chiffre d affaires (commandes terminees)'
\echo '   Grain de sortie : une ligne par produit. Perimetre : status = completed.'
WITH product_revenue AS (
    SELECT
        i.product_id,
        SUM(i.quantity * i.unit_price_cents) AS revenue_cents,
        SUM(i.quantity) AS units_sold
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    WHERE o.status = 'completed'
    GROUP BY i.product_id
)
SELECT
    pr.product_id,
    p.product_name,
    c.category_name,
    ROUND(pr.revenue_cents / 100.0, 2) AS revenue_eur,
    pr.units_sold,
    RANK() OVER (ORDER BY pr.revenue_cents DESC) AS global_rank,
    DENSE_RANK() OVER (ORDER BY pr.revenue_cents DESC) AS global_dense_rank,
    RANK() OVER (PARTITION BY p.category_id ORDER BY pr.revenue_cents DESC) AS rank_in_category
FROM product_revenue AS pr
JOIN core.products AS p ON p.product_id = pr.product_id
JOIN core.categories AS c ON c.category_id = p.category_id
ORDER BY global_rank, pr.product_id;

\echo ''
\echo '== R2. Ex aequo dans le classement des produits'
WITH product_revenue AS (
    SELECT i.product_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    WHERE o.status = 'completed'
    GROUP BY i.product_id
)
SELECT
    ROUND(revenue_cents / 100.0, 2) AS revenue_eur,
    COUNT(*) AS products_sharing_rank,
    STRING_AGG(product_id::text, ', ' ORDER BY product_id) AS product_ids
FROM product_revenue
GROUP BY revenue_cents
HAVING COUNT(*) > 1
ORDER BY revenue_cents DESC;

\echo ''
\echo '== R3. Classement des clients par chiffre d affaires, dans leur ville'
\echo '   Grain de sortie : une ligne par client ayant au moins une commande terminee.'
WITH customer_revenue AS (
    SELECT
        o.customer_id,
        COUNT(DISTINCT o.order_id) AS completed_orders,
        SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.orders AS o
    JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
),
ranked AS (
    SELECT
        cr.customer_id,
        cu.city,
        cr.completed_orders,
        cr.revenue_cents,
        RANK() OVER (PARTITION BY cu.city ORDER BY cr.revenue_cents DESC) AS rank_in_city
    FROM customer_revenue AS cr
    JOIN core.customers AS cu ON cu.customer_id = cr.customer_id
)
SELECT
    city,
    rank_in_city,
    customer_id,
    completed_orders,
    ROUND(revenue_cents / 100.0, 2) AS revenue_eur
FROM ranked
WHERE rank_in_city <= 3
ORDER BY city, rank_in_city, customer_id;

\echo ''
\echo '== R4. Effet d une duplication : classement calcule avec le catalogue brut (doublon du produit 3)'
WITH clean_revenue AS (
    SELECT i.product_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    JOIN core.products AS p ON p.product_id = i.product_id
    WHERE o.status = 'completed'
    GROUP BY i.product_id
),
raw_revenue AS (
    SELECT i.product_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.order_items AS i
    JOIN core.orders AS o ON o.order_id = i.order_id
    JOIN reception.products AS rp ON rp.product_id::integer = i.product_id
    WHERE o.status = 'completed'
    GROUP BY i.product_id
),
compared AS (
    SELECT
        c.product_id,
        c.revenue_cents AS clean_revenue_cents,
        r.revenue_cents AS raw_revenue_cents,
        RANK() OVER (ORDER BY c.revenue_cents DESC) AS clean_rank,
        RANK() OVER (ORDER BY r.revenue_cents DESC) AS raw_rank
    FROM clean_revenue AS c
    JOIN raw_revenue AS r ON r.product_id = c.product_id
)
SELECT
    product_id,
    ROUND(clean_revenue_cents / 100.0, 2) AS clean_revenue_eur,
    ROUND(raw_revenue_cents / 100.0, 2) AS raw_revenue_eur,
    clean_rank,
    raw_rank
FROM compared
WHERE clean_rank <> raw_rank OR clean_revenue_cents <> raw_revenue_cents
ORDER BY raw_rank, product_id;

\echo ''
\echo '== R4 bis. Total du chiffre d affaires selon le catalogue utilise'
SELECT
    (SELECT ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2)
        FROM core.order_items AS i
        JOIN core.orders AS o ON o.order_id = i.order_id
        JOIN core.products AS p ON p.product_id = i.product_id
        WHERE o.status = 'completed') AS with_clean_catalog_eur,
    (SELECT ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2)
        FROM core.order_items AS i
        JOIN core.orders AS o ON o.order_id = i.order_id
        JOIN reception.products AS rp ON rp.product_id::integer = i.product_id
        WHERE o.status = 'completed') AS with_raw_catalog_eur;
