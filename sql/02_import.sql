BEGIN;

\copy reception.customers (customer_id, customer_name, city) FROM '/s1/donnees/customers.csv' WITH (FORMAT csv, HEADER true)
\copy reception.orders (order_id, customer_id, ordered_on, status) FROM '/s1/donnees/orders.csv' WITH (FORMAT csv, HEADER true)
\copy reception.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents) FROM '/s1/donnees/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy reception.payments (document) FROM '/s1/donnees/payments.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')


INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'customers.csv', r.source_row, r.customer_id, 'doublon'
FROM reception.customers AS r
WHERE r.source_row > (
    SELECT MIN(r2.source_row)
    FROM reception.customers AS r2
    WHERE r2.customer_id = r.customer_id
);

INSERT INTO core.customers (customer_id, customer_name, city)
SELECT r.customer_id::integer, r.customer_name, r.city
FROM reception.customers AS r
WHERE NOT EXISTS (
    SELECT 1 FROM quality.rejected_rows AS q
    WHERE q.source_file = 'customers.csv' AND q.source_row = r.source_row
);


INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'orders.csv', r.source_row, r.order_id, 'doublon'
FROM reception.orders AS r
WHERE r.source_row > (
    SELECT MIN(r2.source_row)
    FROM reception.orders AS r2
    WHERE r2.order_id = r.order_id
);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'orders.csv', r.source_row, r.order_id, 'statut inconnu'
FROM reception.orders AS r
WHERE r.status NOT IN ('completed', 'pending', 'cancelled');

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'orders.csv', r.source_row, r.order_id, 'client inexistant'
FROM reception.orders AS r
WHERE NOT EXISTS (
    SELECT 1 FROM core.customers AS c
    WHERE c.customer_id = r.customer_id::integer
);

INSERT INTO core.orders (order_id, customer_id, ordered_on, status)
SELECT r.order_id::integer, r.customer_id::integer, r.ordered_on::date, r.status
FROM reception.orders AS r
WHERE NOT EXISTS (
    SELECT 1 FROM quality.rejected_rows AS q
    WHERE q.source_file = 'orders.csv' AND q.source_row = r.source_row
);


INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'order_items.csv', r.source_row, r.order_item_id, 'doublon'
FROM reception.order_items AS r
WHERE r.source_row > (
    SELECT MIN(r2.source_row)
    FROM reception.order_items AS r2
    WHERE r2.order_item_id = r.order_item_id
);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'order_items.csv', r.source_row, r.order_item_id, 'commande inexistante'
FROM reception.order_items AS r
WHERE NOT EXISTS (
    SELECT 1 FROM core.orders AS o
    WHERE o.order_id = r.order_id::integer
);

INSERT INTO core.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents)
SELECT
    r.order_item_id::integer,
    r.order_id::integer,
    r.product_id::integer,
    r.quantity::integer,
    r.unit_price_cents::integer
FROM reception.order_items AS r
WHERE NOT EXISTS (
    SELECT 1 FROM quality.rejected_rows AS q
    WHERE q.source_file = 'order_items.csv' AND q.source_row = r.source_row
);


CREATE TEMP TABLE received_payments AS
SELECT r.source_row, p.payment_id, p.order_id, p.paid_on, p.amount_cents, p.status
FROM reception.payments AS r
CROSS JOIN LATERAL jsonb_to_record(r.document)
    AS p (payment_id integer, order_id integer, paid_on date, amount_cents integer, status text);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'payments.ndjson', p.source_row, p.payment_id::text, 'doublon'
FROM received_payments AS p
WHERE p.source_row > (
    SELECT MIN(p2.source_row)
    FROM received_payments AS p2
    WHERE p2.payment_id = p.payment_id
);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'payments.ndjson', p.source_row, p.payment_id::text, 'statut inconnu'
FROM received_payments AS p
WHERE p.status NOT IN ('captured', 'pending');

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'payments.ndjson', p.source_row, p.payment_id::text, 'commande inexistante'
FROM received_payments AS p
WHERE NOT EXISTS (
    SELECT 1 FROM core.orders AS o
    WHERE o.order_id = p.order_id
);

INSERT INTO core.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT p.payment_id, p.order_id, p.paid_on, p.amount_cents, p.status
FROM received_payments AS p
WHERE NOT EXISTS (
    SELECT 1 FROM quality.rejected_rows AS q
    WHERE q.source_file = 'payments.ndjson' AND q.source_row = p.source_row
);

COMMIT;
