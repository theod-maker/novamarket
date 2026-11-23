\echo ''
\echo '== Volumes recus, integres et rejetes par source'
SELECT
    source_file,
    received_rows,
    integrated_rows,
    rejected_rows,
    received_rows - integrated_rows - rejected_rows AS gap_must_be_zero
FROM (
    SELECT
        'customers.csv' AS source_file,
        (SELECT COUNT(*) FROM reception.customers) AS received_rows,
        (SELECT COUNT(*) FROM core.customers) AS integrated_rows,
        (SELECT COUNT(DISTINCT source_row) FROM quality.rejected_rows
            WHERE source_file = 'customers.csv') AS rejected_rows
    UNION ALL
    SELECT
        'orders.csv',
        (SELECT COUNT(*) FROM reception.orders),
        (SELECT COUNT(*) FROM core.orders),
        (SELECT COUNT(DISTINCT source_row) FROM quality.rejected_rows
            WHERE source_file = 'orders.csv')
    UNION ALL
    SELECT
        'order_items.csv',
        (SELECT COUNT(*) FROM reception.order_items),
        (SELECT COUNT(*) FROM core.order_items),
        (SELECT COUNT(DISTINCT source_row) FROM quality.rejected_rows
            WHERE source_file = 'order_items.csv')
    UNION ALL
    SELECT
        'payments.ndjson',
        (SELECT COUNT(*) FROM reception.payments),
        (SELECT COUNT(*) FROM core.payments),
        (SELECT COUNT(DISTINCT source_row) FROM quality.rejected_rows
            WHERE source_file = 'payments.ndjson')
) AS volumes;

\echo ''
\echo '== Journal des rejets'
SELECT source_file, source_row, source_key, reason
FROM quality.rejected_rows
ORDER BY source_file, source_row;

\echo ''
\echo '== Detail des lignes rejetees dans le fichier brut'
SELECT r.*
FROM reception.order_items AS r
WHERE r.source_row IN (
    SELECT source_row FROM quality.rejected_rows WHERE source_file = 'order_items.csv'
)
ORDER BY r.source_row;
