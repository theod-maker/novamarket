\echo '== Volumes recus, integres et rejetes par source'
WITH volumes AS (
    SELECT 'customers.csv' AS source_file,
        (SELECT count(*) FROM reception.customers) AS received_rows,
        (SELECT count(*) FROM core.customers) AS integrated_rows
    UNION ALL
    SELECT 'orders.csv',
        (SELECT count(*) FROM reception.orders),
        (SELECT count(*) FROM core.orders)
    UNION ALL
    SELECT 'order_items.csv',
        (SELECT count(*) FROM reception.order_items),
        (SELECT count(*) FROM core.order_items)
    UNION ALL
    SELECT 'payments.ndjson',
        (SELECT count(*) FROM reception.payments),
        (SELECT count(*) FROM core.payments)
)
SELECT
    v.source_file,
    v.received_rows,
    v.integrated_rows,
    count(r.rejection_id) AS rejected_rows,
    v.received_rows = v.integrated_rows + count(r.rejection_id) AS is_balanced
FROM volumes AS v
LEFT JOIN quality.rejected_rows AS r ON r.source_file = v.source_file
GROUP BY v.source_file, v.received_rows, v.integrated_rows
ORDER BY v.source_file;

\echo '== Journal des rejets'
SELECT source_file, source_row, source_key, reason, raw_record
FROM quality.rejected_rows
ORDER BY source_file, source_row;

\echo '== Controles de coherence (chaque ligne doit valoir 0)'
SELECT 'orders_without_items' AS check_name, count(*) AS failing_rows
FROM core.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM core.order_items AS i WHERE i.order_id = o.order_id)
UNION ALL
SELECT 'payments_before_order', count(*)
FROM core.payments AS p
JOIN core.orders AS o ON o.order_id = p.order_id
WHERE p.paid_on < o.ordered_on
UNION ALL
SELECT 'completed_orders_items_vs_captured_mismatch', count(*)
FROM core.orders AS o
JOIN (
    SELECT order_id, sum(quantity * unit_price_cents) AS items_cents
    FROM core.order_items
    GROUP BY order_id
) AS i ON i.order_id = o.order_id
LEFT JOIN (
    SELECT order_id, sum(amount_cents) FILTER (WHERE status = 'captured') AS captured_cents
    FROM core.payments
    GROUP BY order_id
) AS p ON p.order_id = o.order_id
WHERE o.status = 'completed'
    AND i.items_cents IS DISTINCT FROM p.captured_cents;
