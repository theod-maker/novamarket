\set q_wide 'SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1'

\echo ''
\echo '== X1. Repartition des ventes par magasin (selectivite des filtres)'
SELECT
    CASE WHEN store_id = 1 THEN 'magasin 1' ELSE 'autres magasins' END AS store_group,
    COUNT(DISTINCT store_id) AS stores,
    COUNT(*) AS sales,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct
FROM benchmark.benchmark_sales
GROUP BY store_group;

SELECT store_id, COUNT(*) AS sales
FROM benchmark.benchmark_sales
WHERE store_id IN (1, 42)
GROUP BY store_id
ORDER BY store_id;

\echo ''
\echo '== X2. Index inefficace : on force l index sur le filtre large (enable_seqscan = off)'
BEGIN;
SET LOCAL enable_seqscan = off;
\echo '### forced run 1 (premier passage)'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
\echo '### forced run 2'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
\echo '### forced run 3'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
\echo '### forced run 4'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
ROLLBACK;

\echo ''
\echo '== X3. Multiplication des lignes : jointure ventes x campagnes pour le magasin 42'
SELECT
    (SELECT COUNT(*) FROM benchmark.benchmark_sales WHERE store_id = 42) AS sales_rows,
    (SELECT COUNT(*) FROM benchmark.campaign_assignments WHERE store_id = 42) AS campaigns,
    (SELECT COUNT(*) FROM benchmark.benchmark_sales AS s
        JOIN benchmark.campaign_assignments AS c ON c.store_id = s.store_id
        WHERE s.store_id = 42) AS joined_rows,
    (SELECT SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42)
        AS true_amount_cents,
    (SELECT SUM(s.amount_cents) FROM benchmark.benchmark_sales AS s
        JOIN benchmark.campaign_assignments AS c ON c.store_id = s.store_id
        WHERE s.store_id = 42) AS joined_amount_cents;

EXPLAIN (ANALYZE, BUFFERS)
SELECT c.campaign_id, COUNT(*) AS sales, SUM(s.amount_cents) AS amount_cents
FROM benchmark.benchmark_sales AS s
JOIN benchmark.campaign_assignments AS c ON c.store_id = s.store_id
WHERE s.store_id = 42
GROUP BY c.campaign_id;

\echo ''
\echo '== X4. Ecart entre lignes estimees et reelles : colonnes correlees zone_id et channel_id'
SELECT COUNT(*) AS rows_where_zone_equals_channel
FROM benchmark.benchmark_sales
WHERE zone_id = channel_id;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 3;

EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 4;

\echo ''
\echo '== X5. Correction de l estimation avec des statistiques etendues (essai annule par ROLLBACK)'
BEGIN;
CREATE STATISTICS benchmark.sales_zone_channel_stats (dependencies)
    ON zone_id, channel_id FROM benchmark.benchmark_sales;
ANALYZE benchmark.benchmark_sales;
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM benchmark.benchmark_sales WHERE zone_id = 3 AND channel_id = 3;
ROLLBACK;
