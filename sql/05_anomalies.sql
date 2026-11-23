\echo ''
\echo '== A1. Rejets par cause'
SELECT source_file, reason, count(*) AS rejected_rows, string_agg(source_key, ', ') AS source_keys
FROM quality.rejected_rows
GROUP BY source_file, reason
ORDER BY source_file, reason;

\echo ''
\echo '== A2. Effet du doublon de ligne s il avait ete integre (commandes terminees)'
SELECT
    round((
        SELECT sum(r.quantity::integer * r.unit_price_cents::integer)
        FROM reception.order_items AS r
        JOIN core.orders AS o ON o.order_id::text = r.order_id
        WHERE o.status = 'completed'
    ) / 100.0, 2) AS revenue_from_raw_lines_eur,
    round((
        SELECT sum(i.quantity * i.unit_price_cents)
        FROM core.order_items AS i
        JOIN core.orders AS o ON o.order_id = i.order_id
        WHERE o.status = 'completed'
    ) / 100.0, 2) AS revenue_from_core_eur;

\echo ''
\echo '== A3. Paiements identiques (meme commande, date, montant, statut) : doublons ou fractionnement ?'
WITH identical_groups AS (
    SELECT order_id, paid_on, amount_cents, status, count(*) AS payment_count,
        string_agg(payment_id::text, ', ' ORDER BY payment_id) AS payment_ids
    FROM core.payments
    GROUP BY order_id, paid_on, amount_cents, status
    HAVING count(*) > 1
),
item_totals AS (
    SELECT order_id, sum(quantity * unit_price_cents) AS items_cents
    FROM core.order_items
    GROUP BY order_id
),
payment_totals AS (
    SELECT order_id, sum(amount_cents) AS paid_cents
    FROM core.payments
    GROUP BY order_id
)
SELECT
    count(*) AS identical_groups,
    count(*) FILTER (WHERE pt.paid_cents = it.items_cents) AS groups_where_all_payments_needed,
    count(*) FILTER (WHERE pt.paid_cents - g.amount_cents = it.items_cents)
        AS groups_where_one_payment_is_extra
FROM identical_groups AS g
JOIN item_totals AS it ON it.order_id = g.order_id
JOIN payment_totals AS pt ON pt.order_id = g.order_id;

\echo ''
\echo '== A3 bis. Exemples de paiements identiques'
SELECT p.order_id, p.payment_id, p.paid_on, p.amount_cents, p.status,
    (SELECT sum(i.quantity * i.unit_price_cents) FROM core.order_items AS i
        WHERE i.order_id = p.order_id) AS order_items_cents
FROM core.payments AS p
WHERE p.order_id IN (
    SELECT order_id FROM core.payments
    GROUP BY order_id, paid_on, amount_cents, status
    HAVING count(*) > 1
    ORDER BY order_id
    LIMIT 3
)
ORDER BY p.order_id, p.payment_id;

\echo ''
\echo '== A4. Multiplication des montants : jointure directe articles x paiements (commandes terminees)'
SELECT
    'jointure_directe' AS method,
    count(*) AS joined_rows,
    round(sum(i.quantity * i.unit_price_cents) / 100.0, 2) AS items_eur,
    round(sum(p.amount_cents) / 100.0, 2) AS payments_eur
FROM core.orders AS o
JOIN core.order_items AS i ON i.order_id = o.order_id
JOIN core.payments AS p ON p.order_id = o.order_id
WHERE o.status = 'completed'
UNION ALL
SELECT
    'agregation_par_commande',
    count(*),
    round(sum(it.items_cents) / 100.0, 2),
    round(sum(pt.paid_cents) / 100.0, 2)
FROM core.orders AS o
JOIN (
    SELECT order_id, sum(quantity * unit_price_cents) AS items_cents
    FROM core.order_items GROUP BY order_id
) AS it ON it.order_id = o.order_id
JOIN (
    SELECT order_id, sum(amount_cents) AS paid_cents
    FROM core.payments GROUP BY order_id
) AS pt ON pt.order_id = o.order_id
WHERE o.status = 'completed';

\echo ''
\echo '== A5. Impact du statut de commande sur le chiffre d affaires'
WITH item_totals AS (
    SELECT order_id, sum(quantity * unit_price_cents) AS items_cents
    FROM core.order_items
    GROUP BY order_id
)
SELECT
    perimeter,
    count(*) AS order_count,
    round(sum(it.items_cents) / 100.0, 2) AS items_eur
FROM core.orders AS o
JOIN item_totals AS it ON it.order_id = o.order_id
CROSS JOIN LATERAL (
    VALUES
        ('1_completed', o.status = 'completed'),
        ('2_completed_pending', o.status IN ('completed', 'pending')),
        ('3_tous_statuts', true)
) AS scope (perimeter, is_included)
WHERE scope.is_included
GROUP BY perimeter
ORDER BY perimeter;

\echo ''
\echo '== A6. Commandes annulees avec paiement encaisse'
SELECT
    count(DISTINCT o.order_id) AS cancelled_orders_with_capture,
    count(*) AS captured_payments,
    round(sum(p.amount_cents) / 100.0, 2) AS captured_eur
FROM core.orders AS o
JOIN core.payments AS p ON p.order_id = o.order_id
WHERE o.status = 'cancelled' AND p.status = 'captured';
