\echo ''
\echo '== A1. Rejets par cause'
SELECT source_file, reason, COUNT(*) AS rejected_rows
FROM quality.rejected_rows
GROUP BY source_file, reason
ORDER BY source_file, reason;

\echo ''
\echo '== A2. Effet du doublon : montant des commandes terminees avant et apres rejet'
SELECT
    (SELECT ROUND(SUM(r.quantity::integer * r.unit_price_cents::integer) / 100.0, 2)
        FROM reception.order_items AS r
        JOIN core.orders AS o ON o.order_id = r.order_id::integer
        WHERE o.status = 'completed') AS with_duplicate_eur,
    (SELECT ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2)
        FROM core.order_items AS i
        JOIN core.orders AS o ON o.order_id = i.order_id
        WHERE o.status = 'completed') AS without_duplicate_eur;

\echo ''
\echo '== A3. Paiements identiques (meme commande, meme date, meme montant)'
SELECT COUNT(*) AS identical_payment_groups
FROM (
    SELECT order_id, paid_on, amount_cents
    FROM core.payments
    GROUP BY order_id, paid_on, amount_cents
    HAVING COUNT(*) > 1
) AS identical_groups;

\echo ''
\echo '== A3 bis. Exemples : les deux paiements ensemble egalent le montant de la commande'
SELECT
    p.order_id,
    COUNT(*) AS payment_count,
    SUM(p.amount_cents) AS total_paid_cents,
    (SELECT SUM(i.quantity * i.unit_price_cents)
        FROM core.order_items AS i
        WHERE i.order_id = p.order_id) AS order_items_cents
FROM core.payments AS p
GROUP BY p.order_id, p.paid_on, p.amount_cents
HAVING COUNT(*) > 1
ORDER BY p.order_id
LIMIT 5;

\echo ''
\echo '== A4. Piege de la jointure articles x paiements (commandes terminees)'
SELECT
    COUNT(*) AS joined_rows,
    ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2) AS items_eur_wrong,
    ROUND(SUM(p.amount_cents) / 100.0, 2) AS payments_eur_wrong
FROM core.orders AS o
JOIN core.order_items AS i ON i.order_id = o.order_id
JOIN core.payments AS p ON p.order_id = o.order_id
WHERE o.status = 'completed';

\echo ''
\echo '== A4 bis. Bonne methode : chaque total calcule separement'
SELECT
    (SELECT ROUND(SUM(i.quantity * i.unit_price_cents) / 100.0, 2)
        FROM core.order_items AS i
        JOIN core.orders AS o ON o.order_id = i.order_id
        WHERE o.status = 'completed') AS items_eur,
    (SELECT ROUND(SUM(p.amount_cents) / 100.0, 2)
        FROM core.payments AS p
        JOIN core.orders AS o ON o.order_id = p.order_id
        WHERE o.status = 'completed') AS payments_eur;

\echo ''
\echo '== A5. Commandes annulees mais encaissees'
SELECT
    COUNT(DISTINCT o.order_id) AS cancelled_orders,
    COUNT(*) AS captured_payments,
    ROUND(SUM(p.amount_cents) / 100.0, 2) AS captured_eur
FROM core.orders AS o
JOIN core.payments AS p ON p.order_id = o.order_id
WHERE o.status = 'cancelled' AND p.status = 'captured';
