\echo ''
\echo '== I1. Nombre de commandes par statut'
SELECT status, COUNT(*) AS order_count
FROM core.orders
GROUP BY status
ORDER BY order_count DESC;

\echo ''
\echo '== I2. Clients sans commande'
SELECT COUNT(*) AS customers_without_order
FROM core.customers AS c
WHERE NOT EXISTS (
    SELECT 1 FROM core.orders AS o WHERE o.customer_id = c.customer_id
);

\echo ''
\echo '== I2 bis. Liste des clients sans commande'
SELECT c.customer_id, c.customer_name, c.city
FROM core.customers AS c
WHERE NOT EXISTS (
    SELECT 1 FROM core.orders AS o WHERE o.customer_id = c.customer_id
)
ORDER BY c.customer_id;

\echo ''
\echo '== I3. Montant des lignes des commandes terminees et panier moyen'
\echo '   Denominateur du panier moyen : nombre de commandes terminees (COUNT DISTINCT order_id).'
SELECT
    COUNT(DISTINCT o.order_id) AS completed_orders,
    SUM(i.quantity * i.unit_price_cents) AS revenue_cents,
    ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS revenue_eur,
    ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0 / COUNT(DISTINCT o.order_id), 2)
        AS average_basket_eur
FROM core.orders AS o
JOIN core.order_items AS i ON i.order_id = o.order_id
WHERE o.status = 'completed';

\echo ''
\echo '== I4. Rapprochement : montant des articles par statut de commande'
SELECT
    o.status,
    COUNT(DISTINCT o.order_id) AS order_count,
    ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS items_eur
FROM core.orders AS o
JOIN core.order_items AS i ON i.order_id = o.order_id
GROUP BY o.status
ORDER BY o.status;

\echo ''
\echo '== I4 bis. Rapprochement : montant des paiements par statut de commande'
SELECT
    o.status AS order_status,
    p.status AS payment_status,
    COUNT(*) AS payment_count,
    ROUND(SUM(p.amount_cents) / 100.0, 2) AS payments_eur
FROM core.orders AS o
JOIN core.payments AS p ON p.order_id = o.order_id
GROUP BY o.status, p.status
ORDER BY o.status, p.status;
