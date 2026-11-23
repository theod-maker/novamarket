\echo ''
\echo '== S1. Segmentation des clients en quartiles de chiffre d affaires (NTILE)'
\echo '   Population : clients avec au moins une commande terminee.'
\echo '   Mesure : CA des lignes des commandes terminees. Ordre : CA decroissant, puis customer_id.'
WITH customer_revenue AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.orders AS o
    JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
),
segmented AS (
    SELECT
        customer_id,
        revenue_cents,
        NTILE(4) OVER (ORDER BY revenue_cents DESC, customer_id) AS quartile
    FROM customer_revenue
)
SELECT
    quartile,
    COUNT(*) AS customers,
    ROUND(MIN(revenue_cents) / 100.0, 2) AS min_revenue_eur,
    ROUND(MAX(revenue_cents) / 100.0, 2) AS max_revenue_eur,
    ROUND(SUM(revenue_cents) / 100.0, 2) AS revenue_eur,
    ROUND(100.0 * SUM(revenue_cents) / SUM(SUM(revenue_cents)) OVER (), 1) AS revenue_share_pct
FROM segmented
GROUP BY quartile
ORDER BY quartile;

\echo ''
\echo '== S2. Population exclue de la segmentation'
SELECT
    (SELECT COUNT(*) FROM core.customers) AS all_customers,
    (SELECT COUNT(DISTINCT customer_id) FROM core.orders WHERE status = 'completed')
        AS segmented_customers,
    (SELECT COUNT(*) FROM core.customers AS c
        WHERE NOT EXISTS (SELECT 1 FROM core.orders AS o WHERE o.customer_id = c.customer_id))
        AS customers_without_order,
    (SELECT COUNT(*) FROM core.customers AS c
        WHERE EXISTS (SELECT 1 FROM core.orders AS o WHERE o.customer_id = c.customer_id)
            AND NOT EXISTS (
                SELECT 1 FROM core.orders AS o
                WHERE o.customer_id = c.customer_id AND o.status = 'completed'
            ))
        AS customers_without_completed_order;

\echo ''
\echo '== S3. Ex aequo coupes par une frontiere de quartile'
WITH customer_revenue AS (
    SELECT o.customer_id, SUM(i.quantity * i.unit_price_cents) AS revenue_cents
    FROM core.orders AS o
    JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.customer_id
),
segmented AS (
    SELECT
        customer_id,
        revenue_cents,
        NTILE(4) OVER (ORDER BY revenue_cents DESC, customer_id) AS quartile
    FROM customer_revenue
)
SELECT
    ROUND(revenue_cents / 100.0, 2) AS revenue_eur,
    COUNT(*) AS customers_with_same_revenue,
    STRING_AGG(customer_id || ' (Q' || quartile || ')', ', ' ORDER BY customer_id)
        AS customers_and_quartiles
FROM segmented
GROUP BY revenue_cents
HAVING COUNT(DISTINCT quartile) > 1
ORDER BY revenue_cents DESC;
