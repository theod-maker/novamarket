BEGIN;
CREATE SCHEMA s4_exemple;
CREATE TABLE s4_exemple.releves (
    releve_id integer PRIMARY KEY,
    cuve text NOT NULL,
    volume_litres integer NOT NULL
);
INSERT INTO s4_exemple.releves VALUES (1, 'A', 20), (2, 'A', 25), (3, 'B', 10);
COMMIT;
