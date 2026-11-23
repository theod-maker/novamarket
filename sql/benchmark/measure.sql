\set q_selective 'SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 42'
\set q_wide 'SELECT COUNT(*), SUM(amount_cents) FROM benchmark.benchmark_sales WHERE store_id = 1'

\echo ''
\echo '== Phase' :phase
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'benchmark' ORDER BY indexname;

\echo ''
\echo '== Resultat attendu des deux requetes (identique avant et apres index)'
:q_selective;
:q_wide;

\echo ''
\echo '== Plan estime (EXPLAIN sans execution)'
EXPLAIN :q_selective;
EXPLAIN :q_wide;

\echo ''
\echo '### selective run 1 (premier passage)'
EXPLAIN (ANALYZE, BUFFERS) :q_selective;
\echo '### selective run 2'
EXPLAIN (ANALYZE, BUFFERS) :q_selective;
\echo '### selective run 3'
EXPLAIN (ANALYZE, BUFFERS) :q_selective;
\echo '### selective run 4'
EXPLAIN (ANALYZE, BUFFERS) :q_selective;

\echo ''
\echo '### wide run 1 (premier passage)'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
\echo '### wide run 2'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
\echo '### wide run 3'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
\echo '### wide run 4'
EXPLAIN (ANALYZE, BUFFERS) :q_wide;
