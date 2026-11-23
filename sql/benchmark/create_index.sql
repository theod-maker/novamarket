\echo ''
\echo '== Taille de la table avant index'
SELECT
    pg_size_pretty(pg_relation_size('benchmark.benchmark_sales')) AS table_size,
    pg_size_pretty(pg_total_relation_size('benchmark.benchmark_sales')) AS total_size;

\echo ''
\echo '== Creation de l index (duree mesuree par psql)'
\timing on
CREATE INDEX benchmark_sales_store_id_idx ON benchmark.benchmark_sales (store_id);
ANALYZE benchmark.benchmark_sales;
\timing off

\echo ''
\echo '== Taille de l index'
SELECT
    pg_size_pretty(pg_relation_size('benchmark.benchmark_sales_store_id_idx')) AS index_size,
    pg_relation_size('benchmark.benchmark_sales_store_id_idx') AS index_size_bytes,
    pg_size_pretty(pg_total_relation_size('benchmark.benchmark_sales')) AS total_size_with_index;
