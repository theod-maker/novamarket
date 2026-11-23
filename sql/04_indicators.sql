\echo '== I1. Commandes par statut'
SELECT
    status,
    count(*) AS order_count,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS share_pct
FROM core.orders
GROUP BY status
ORDER BY order_count DESC;

\echo '== I2. Clients sans commande'
SELECT
    count(*) AS customers_without_order,
    (SELECT count(*) FROM core.customers) AS total_customers
FROM core.customers AS c
WHERE NOT EXISTS (SELECT 1 FROM core.orders AS o WHERE o.customer_id = c.customer_id);

\echo '== I2 bis. Detail des clients sans commande'
SELECT c.customer_id, c.customer_name, c.city
FROM core.customers AS c
WHERE NOT EXISTS (SELECT 1 FROM core.orders AS o WHERE o.customer_id = c.customer_id)
ORDER BY c.customer_id;

\echo '== I3. Montant des lignes des commandes terminees et panier moyen'
\echo '   Denominateur : nombre de commandes au statut completed (une ligne par commande).'
WITH completed_order_totals AS (
    SELECT
        o.order_id,
        coalesce(sum(i.quantity * i.unit_price_cents), 0) AS order_amount_cents
    FROM core.orders AS o
    LEFT JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.order_id
)
SELECT
    count(*) AS completed_orders,
    sum(order_amount_cents) AS revenue_cents,
    round(sum(order_amount_cents) / 100.0, 2) AS revenue_eur,
    round(avg(order_amount_cents) / 100.0, 2) AS average_basket_eur
FROM completed_order_totals;

\echo '== I3 bis. Par mois de commande'
WITH completed_order_totals AS (
    SELECT
        o.order_id,
        date_trunc('month', o.ordered_on)::date AS order_month,
        coalesce(sum(i.quantity * i.unit_price_cents), 0) AS order_amount_cents
    FROM core.orders AS o
    LEFT JOIN core.order_items AS i ON i.order_id = o.order_id
    WHERE o.status = 'completed'
    GROUP BY o.order_id, order_month
)
SELECT
    order_month,
    count(*) AS completed_orders,
    round(sum(order_amount_cents) / 100.0, 2) AS revenue_eur,
    round(avg(order_amount_cents) / 100.0, 2) AS average_basket_eur
FROM completed_order_totals
GROUP BY order_month
ORDER BY order_month;

\echo '== I4. Rapprochement articles / paiements, agreges par commande avant la jointure'
WITH item_totals AS (
    SELECT order_id, sum(quantity * unit_price_cents) AS items_cents
    FROM core.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT
        order_id,
        count(*) AS payment_count,
        coalesce(sum(amount_cents) FILTER (WHERE status = 'captured'), 0) AS captured_cents,
        coalesce(sum(amount_cents) FILTER (WHERE status = 'pending'), 0) AS pending_cents
    FROM core.payments
    GROUP BY order_id
)
SELECT
    o.status AS order_status,
    count(*) AS order_count,
    round(sum(i.items_cents) / 100.0, 2) AS items_eur,
    round(sum(coalesce(p.captured_cents, 0)) / 100.0, 2) AS captured_eur,
    round(sum(coalesce(p.pending_cents, 0)) / 100.0, 2) AS pending_payments_eur,
    count(*) FILTER (WHERE coalesce(p.payment_count, 0) > 1) AS orders_with_split_payment,
    count(*) FILTER (
        WHERE i.items_cents = coalesce(p.captured_cents, 0) + coalesce(p.pending_cents, 0)
    ) AS orders_fully_matched
FROM core.orders AS o
JOIN item_totals AS i ON i.order_id = o.order_id
LEFT JOIN payment_totals AS p ON p.order_id = o.order_id
GROUP BY o.status
ORDER BY o.status;
