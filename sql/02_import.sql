\copy reception.customers (customer_id, customer_name, city) FROM '/s1/donnees/customers.csv' WITH (FORMAT csv, HEADER true)
\copy reception.orders (order_id, customer_id, ordered_on, status) FROM '/s1/donnees/orders.csv' WITH (FORMAT csv, HEADER true)
\copy reception.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents) FROM '/s1/donnees/order_items.csv' WITH (FORMAT csv, HEADER true)
\copy reception.payments (raw_line) FROM '/s1/donnees/payments.ndjson' WITH (FORMAT csv, QUOTE E'\x01', DELIMITER E'\x02')

CREATE TEMP TABLE checked_customers AS
WITH typed AS (
    SELECT
        r.source_row,
        r.customer_id AS source_key,
        to_jsonb(r) - 'source_row' - 'loaded_at' AS raw_record,
        CASE
            WHEN r.customer_id IS NULL OR r.customer_name IS NULL OR r.city IS NULL
                THEN 'missing_field'
            WHEN NOT pg_input_is_valid(r.customer_id, 'integer')
                THEN 'invalid_type'
        END AS structural_reason,
        CASE WHEN pg_input_is_valid(r.customer_id, 'integer') THEN r.customer_id::integer END
            AS customer_id,
        r.customer_name,
        r.city
    FROM reception.customers AS r
),
ranked AS (
    SELECT
        typed.*,
        row_number() OVER same_id AS id_rank,
        first_value(raw_record) OVER same_id AS first_record
    FROM typed
    WINDOW same_id AS (
        PARTITION BY customer_id, structural_reason IS NULL ORDER BY source_row
    )
)
SELECT
    ranked.*,
    CASE
        WHEN structural_reason IS NOT NULL THEN structural_reason
        WHEN id_rank > 1 AND raw_record = first_record THEN 'duplicate_exact'
        WHEN id_rank > 1 THEN 'duplicate_id_conflict'
    END AS rejection_reason
FROM ranked;

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason, raw_record)
SELECT 'customers.csv', source_row, source_key, rejection_reason, raw_record
FROM checked_customers
WHERE rejection_reason IS NOT NULL;

INSERT INTO core.customers (customer_id, customer_name, city)
SELECT customer_id, customer_name, city
FROM checked_customers
WHERE rejection_reason IS NULL;

CREATE TEMP TABLE checked_orders AS
WITH typed AS (
    SELECT
        r.source_row,
        r.order_id AS source_key,
        to_jsonb(r) - 'source_row' - 'loaded_at' AS raw_record,
        CASE
            WHEN r.order_id IS NULL OR r.customer_id IS NULL OR r.ordered_on IS NULL
                OR r.status IS NULL
                THEN 'missing_field'
            WHEN NOT (
                pg_input_is_valid(r.order_id, 'integer')
                AND pg_input_is_valid(r.customer_id, 'integer')
                AND pg_input_is_valid(r.ordered_on, 'date')
            )
                THEN 'invalid_type'
            WHEN r.status NOT IN ('completed', 'pending', 'cancelled')
                THEN 'invalid_status'
        END AS structural_reason,
        CASE WHEN pg_input_is_valid(r.order_id, 'integer') THEN r.order_id::integer END
            AS order_id,
        CASE WHEN pg_input_is_valid(r.customer_id, 'integer') THEN r.customer_id::integer END
            AS customer_id,
        CASE WHEN pg_input_is_valid(r.ordered_on, 'date') THEN r.ordered_on::date END
            AS ordered_on,
        r.status
    FROM reception.orders AS r
),
ranked AS (
    SELECT
        typed.*,
        row_number() OVER same_id AS id_rank,
        first_value(raw_record) OVER same_id AS first_record
    FROM typed
    WINDOW same_id AS (
        PARTITION BY order_id, structural_reason IS NULL ORDER BY source_row
    )
)
SELECT
    ranked.*,
    CASE
        WHEN structural_reason IS NOT NULL THEN structural_reason
        WHEN id_rank > 1 AND raw_record = first_record THEN 'duplicate_exact'
        WHEN id_rank > 1 THEN 'duplicate_id_conflict'
        WHEN NOT EXISTS (
            SELECT 1 FROM core.customers AS c WHERE c.customer_id = ranked.customer_id
        )
            THEN 'orphan_customer'
    END AS rejection_reason
FROM ranked;

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason, raw_record)
SELECT 'orders.csv', source_row, source_key, rejection_reason, raw_record
FROM checked_orders
WHERE rejection_reason IS NOT NULL;

INSERT INTO core.orders (order_id, customer_id, ordered_on, status)
SELECT order_id, customer_id, ordered_on, status
FROM checked_orders
WHERE rejection_reason IS NULL;

CREATE TEMP TABLE checked_order_items AS
WITH typed AS (
    SELECT
        r.source_row,
        r.order_item_id AS source_key,
        to_jsonb(r) - 'source_row' - 'loaded_at' AS raw_record,
        CASE
            WHEN r.order_item_id IS NULL OR r.order_id IS NULL OR r.product_id IS NULL
                OR r.quantity IS NULL OR r.unit_price_cents IS NULL
                THEN 'missing_field'
            WHEN NOT (
                pg_input_is_valid(r.order_item_id, 'integer')
                AND pg_input_is_valid(r.order_id, 'integer')
                AND pg_input_is_valid(r.product_id, 'integer')
                AND pg_input_is_valid(r.quantity, 'integer')
                AND pg_input_is_valid(r.unit_price_cents, 'integer')
            )
                THEN 'invalid_type'
            WHEN r.quantity::integer <= 0
                THEN 'invalid_quantity'
            WHEN r.unit_price_cents::integer < 0
                THEN 'invalid_price'
        END AS structural_reason,
        CASE WHEN pg_input_is_valid(r.order_item_id, 'integer') THEN r.order_item_id::integer END
            AS order_item_id,
        CASE WHEN pg_input_is_valid(r.order_id, 'integer') THEN r.order_id::integer END
            AS order_id,
        CASE WHEN pg_input_is_valid(r.product_id, 'integer') THEN r.product_id::integer END
            AS product_id,
        CASE WHEN pg_input_is_valid(r.quantity, 'integer') THEN r.quantity::integer END
            AS quantity,
        CASE
            WHEN pg_input_is_valid(r.unit_price_cents, 'integer')
                THEN r.unit_price_cents::integer
        END AS unit_price_cents
    FROM reception.order_items AS r
),
ranked AS (
    SELECT
        typed.*,
        row_number() OVER same_id AS id_rank,
        first_value(raw_record) OVER same_id AS first_record
    FROM typed
    WINDOW same_id AS (
        PARTITION BY order_item_id, structural_reason IS NULL ORDER BY source_row
    )
)
SELECT
    ranked.*,
    CASE
        WHEN structural_reason IS NOT NULL THEN structural_reason
        WHEN id_rank > 1 AND raw_record = first_record THEN 'duplicate_exact'
        WHEN id_rank > 1 THEN 'duplicate_id_conflict'
        WHEN NOT EXISTS (SELECT 1 FROM core.orders AS o WHERE o.order_id = ranked.order_id)
            THEN 'orphan_order'
    END AS rejection_reason
FROM ranked;

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason, raw_record)
SELECT 'order_items.csv', source_row, source_key, rejection_reason, raw_record
FROM checked_order_items
WHERE rejection_reason IS NOT NULL;

INSERT INTO core.order_items (order_item_id, order_id, product_id, quantity, unit_price_cents)
SELECT order_item_id, order_id, product_id, quantity, unit_price_cents
FROM checked_order_items
WHERE rejection_reason IS NULL;

CREATE TEMP TABLE checked_payments AS
WITH parsed AS (
    SELECT
        r.source_row,
        r.raw_line,
        CASE WHEN pg_input_is_valid(r.raw_line, 'jsonb') THEN r.raw_line::jsonb END AS document
    FROM reception.payments AS r
),
typed AS (
    SELECT
        p.source_row,
        p.document ->> 'payment_id' AS source_key,
        coalesce(p.document, jsonb_build_object('raw_line', p.raw_line)) AS raw_record,
        CASE
            WHEN p.document IS NULL OR jsonb_typeof(p.document) <> 'object'
                THEN 'invalid_json'
            WHEN p.document ->> 'payment_id' IS NULL OR p.document ->> 'order_id' IS NULL
                OR p.document ->> 'paid_on' IS NULL OR p.document ->> 'amount_cents' IS NULL
                OR p.document ->> 'status' IS NULL
                THEN 'missing_field'
            WHEN NOT (
                pg_input_is_valid(p.document ->> 'payment_id', 'integer')
                AND pg_input_is_valid(p.document ->> 'order_id', 'integer')
                AND pg_input_is_valid(p.document ->> 'paid_on', 'date')
                AND pg_input_is_valid(p.document ->> 'amount_cents', 'integer')
            )
                THEN 'invalid_type'
            WHEN (p.document ->> 'amount_cents')::integer <= 0
                THEN 'invalid_amount'
            WHEN p.document ->> 'status' NOT IN ('captured', 'pending')
                THEN 'invalid_status'
        END AS structural_reason,
        CASE
            WHEN pg_input_is_valid(p.document ->> 'payment_id', 'integer')
                THEN (p.document ->> 'payment_id')::integer
        END AS payment_id,
        CASE
            WHEN pg_input_is_valid(p.document ->> 'order_id', 'integer')
                THEN (p.document ->> 'order_id')::integer
        END AS order_id,
        CASE
            WHEN pg_input_is_valid(p.document ->> 'paid_on', 'date')
                THEN (p.document ->> 'paid_on')::date
        END AS paid_on,
        CASE
            WHEN pg_input_is_valid(p.document ->> 'amount_cents', 'integer')
                THEN (p.document ->> 'amount_cents')::integer
        END AS amount_cents,
        p.document ->> 'status' AS status
    FROM parsed AS p
),
ranked AS (
    SELECT
        typed.*,
        row_number() OVER same_id AS id_rank,
        first_value(raw_record) OVER same_id AS first_record
    FROM typed
    WINDOW same_id AS (
        PARTITION BY payment_id, structural_reason IS NULL ORDER BY source_row
    )
)
SELECT
    ranked.*,
    CASE
        WHEN structural_reason IS NOT NULL THEN structural_reason
        WHEN id_rank > 1 AND raw_record = first_record THEN 'duplicate_exact'
        WHEN id_rank > 1 THEN 'duplicate_id_conflict'
        WHEN NOT EXISTS (SELECT 1 FROM core.orders AS o WHERE o.order_id = ranked.order_id)
            THEN 'orphan_order'
    END AS rejection_reason
FROM ranked;

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason, raw_record)
SELECT 'payments.ndjson', source_row, source_key, rejection_reason, raw_record
FROM checked_payments
WHERE rejection_reason IS NOT NULL;

INSERT INTO core.payments (payment_id, order_id, paid_on, amount_cents, status)
SELECT payment_id, order_id, paid_on, amount_cents, status
FROM checked_payments
WHERE rejection_reason IS NULL;

ANALYZE core.customers, core.orders, core.order_items, core.payments;
