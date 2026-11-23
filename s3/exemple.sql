BEGIN;
CREATE TEMP TABLE releves AS
SELECT n AS releve_id, n % 1000 AS capteur, n % 70 AS valeur
FROM generate_series(1, 100000) AS s(n);
ANALYZE releves;

EXPLAIN SELECT avg(valeur) FROM releves WHERE capteur = 31;
EXPLAIN (ANALYZE, BUFFERS) SELECT avg(valeur) FROM releves WHERE capteur = 31;
CREATE INDEX releves_capteur_idx ON releves (capteur);
EXPLAIN (ANALYZE, BUFFERS) SELECT avg(valeur) FROM releves WHERE capteur = 31;
DROP INDEX releves_capteur_idx;
ROLLBACK;
