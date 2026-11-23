SET client_min_messages = warning;

DROP SCHEMA IF EXISTS core CASCADE;
DROP SCHEMA IF EXISTS quality CASCADE;
DROP SCHEMA IF EXISTS reception CASCADE;

CREATE SCHEMA reception;
CREATE SCHEMA quality;
CREATE SCHEMA core;

CREATE TABLE reception.customers (
    source_row bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id text,
    customer_name text,
    city text,
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reception.orders (
    source_row bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id text,
    customer_id text,
    ordered_on text,
    status text,
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reception.order_items (
    source_row bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id text,
    order_id text,
    product_id text,
    quantity text,
    unit_price_cents text,
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE reception.payments (
    source_row bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    raw_line text,
    loaded_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE quality.rejected_rows (
    rejection_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_file text NOT NULL,
    source_row bigint NOT NULL,
    source_key text,
    reason text NOT NULL,
    raw_record jsonb NOT NULL,
    rejected_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (source_file, source_row)
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

CREATE INDEX order_items_order_id_idx ON core.order_items (order_id);
CREATE INDEX payments_order_id_idx ON core.payments (order_id);
CREATE INDEX orders_customer_id_idx ON core.orders (customer_id);
