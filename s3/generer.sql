\timing on
BEGIN;
CREATE SCHEMA benchmark;

CREATE TABLE benchmark.benchmark_sales AS
SELECT n AS sale_id,
       DATE '2026-01-01' + ((n - 1) / 100000)::integer AS sold_on,
       CASE WHEN n % 20 <> 0 THEN 1 ELSE ((n / 20) % 5000 + 2)::integer END AS store_id,
       (1 + n % 10)::smallint AS zone_id,
       (1 + n % 10)::smallint AS channel_id,
       (500 + (n * 137) % 20000)::integer AS amount_cents
FROM generate_series(1::bigint, 10000000::bigint) AS series(n);

CREATE TABLE benchmark.campaign_assignments (
    store_id integer NOT NULL,
    campaign_id integer NOT NULL,
    PRIMARY KEY (store_id, campaign_id)
);
INSERT INTO benchmark.campaign_assignments VALUES (42, 101), (42, 102), (51, 101), (52, 103);

ANALYZE benchmark.benchmark_sales;
ANALYZE benchmark.campaign_assignments;
COMMIT;
