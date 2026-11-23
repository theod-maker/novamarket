BEGIN;

DROP SCHEMA IF EXISTS core CASCADE;
DROP SCHEMA IF EXISTS quality CASCADE;
DROP SCHEMA IF EXISTS reception CASCADE;

CREATE SCHEMA reception;
CREATE SCHEMA quality;
CREATE SCHEMA core;

CREATE TABLE reception.customers (
    source_row serial PRIMARY KEY,
    customer_id text,
    customer_name text,
    city text
);

CREATE TABLE reception.orders (
    source_row serial PRIMARY KEY,
    order_id text,
    customer_id text,
    ordered_on text,
    status text
);

CREATE TABLE reception.order_items (
    source_row serial PRIMARY KEY,
    order_item_id text,
    order_id text,
    product_id text,
    quantity text,
    unit_price_cents text
);

CREATE TABLE reception.payments (
    source_row serial PRIMARY KEY,
    document jsonb
);

CREATE TABLE quality.rejected_rows (
    rejection_id serial PRIMARY KEY,
    source_file text NOT NULL,
    source_row integer NOT NULL,
    source_key text,
    reason text NOT NULL
);

CREATE TABLE core.customers (
    customer_id integer PRIMARY KEY,
    customer_name text NOT NULL,
    city text NOT NULL
);

CREATE TABLE core.orders (
    order_id integer PRIMARY KEY,
    customer_id integer NOT NULL REFERENCES core.customers (customer_id),
    ordered_on date NOT NULL,
    status text NOT NULL CHECK (status IN ('completed', 'pending', 'cancelled'))
);

CREATE TABLE core.order_items (
    order_item_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES core.orders (order_id),
    product_id integer NOT NULL,
    quantity integer NOT NULL CHECK (quantity > 0),
    unit_price_cents integer NOT NULL CHECK (unit_price_cents >= 0)
);

CREATE TABLE core.payments (
    payment_id integer PRIMARY KEY,
    order_id integer NOT NULL REFERENCES core.orders (order_id),
    paid_on date NOT NULL,
    amount_cents integer NOT NULL CHECK (amount_cents > 0),
    status text NOT NULL CHECK (status IN ('captured', 'pending'))
);

COMMIT;
