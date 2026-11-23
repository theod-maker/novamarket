BEGIN;

CREATE TEMP TABLE salles (
    salle_id integer PRIMARY KEY,
    nom text NOT NULL
);
CREATE TEMP TABLE reservations (
    reservation_id integer PRIMARY KEY,
    salle_id integer NOT NULL REFERENCES salles(salle_id),
    heures integer NOT NULL CHECK (heures > 0)
);
\copy salles (salle_id, nom) FROM '/s1/exemple/salles.csv' WITH (FORMAT csv, HEADER true)

CREATE TEMP TABLE reception_json (document jsonb);
\copy reception_json (document) FROM '/s1/exemple/reservations.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')
INSERT INTO reservations (reservation_id, salle_id, heures)
SELECT r.reservation_id, r.salle_id, r.heures
FROM reception_json
CROSS JOIN LATERAL jsonb_to_record(document) AS r(reservation_id integer, salle_id integer, heures integer);

SELECT s.nom, count(r.reservation_id) AS reservations, coalesce(sum(r.heures), 0) AS heures
FROM salles AS s
LEFT JOIN reservations AS r ON r.salle_id = s.salle_id
GROUP BY s.salle_id, s.nom
ORDER BY s.salle_id;

ROLLBACK;
