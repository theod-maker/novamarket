BEGIN;

CREATE TABLE reception.categories (
    source_row serial PRIMARY KEY,
    category_id text,
    category_name text,
    parent_category_id text
);

CREATE TABLE reception.products (
    source_row serial PRIMARY KEY,
    product_id text,
    sku text,
    product_name text,
    category_id text,
    first_listed_on text
);

CREATE TABLE core.categories (
    category_id integer PRIMARY KEY,
    category_name text NOT NULL,
    parent_category_id integer REFERENCES core.categories (category_id),
    CHECK (parent_category_id <> category_id)
);

CREATE TABLE core.products (
    product_id integer PRIMARY KEY,
    sku text NOT NULL UNIQUE,
    product_name text NOT NULL,
    category_id integer NOT NULL REFERENCES core.categories (category_id),
    first_listed_on date NOT NULL
);

\copy reception.categories (category_id, category_name, parent_category_id) FROM '/tmp/novamarket-s2/categories.csv' WITH (FORMAT csv, HEADER true)
\copy reception.products (product_id, sku, product_name, category_id, first_listed_on) FROM '/tmp/novamarket-s2/products.csv' WITH (FORMAT csv, HEADER true)


INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'categories.csv', r.source_row, r.category_id, 'doublon'
FROM reception.categories AS r
WHERE r.source_row NOT IN (
    SELECT MIN(source_row)
    FROM reception.categories
    GROUP BY category_id
);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'categories.csv', r.source_row, r.category_id, 'parent inexistant'
FROM reception.categories AS r
WHERE r.parent_category_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM reception.categories AS p
        WHERE p.category_id = r.parent_category_id
    );

INSERT INTO core.categories (category_id, category_name, parent_category_id)
SELECT r.category_id::integer, r.category_name, r.parent_category_id::integer
FROM reception.categories AS r
WHERE NOT EXISTS (
    SELECT 1 FROM quality.rejected_rows AS q
    WHERE q.source_file = 'categories.csv' AND q.source_row = r.source_row
);


INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'products.csv', r.source_row, r.product_id, 'doublon'
FROM reception.products AS r
WHERE r.source_row NOT IN (
    SELECT MIN(source_row)
    FROM reception.products
    GROUP BY product_id
);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'products.csv', r.source_row, r.product_id, 'sku partage avec un autre produit'
FROM reception.products AS r
WHERE r.sku IN (
    SELECT sku
    FROM reception.products
    GROUP BY sku
    HAVING COUNT(DISTINCT product_id) > 1
);

INSERT INTO quality.rejected_rows (source_file, source_row, source_key, reason)
SELECT 'products.csv', r.source_row, r.product_id, 'categorie inexistante'
FROM reception.products AS r
WHERE NOT EXISTS (
    SELECT 1 FROM core.categories AS c
    WHERE c.category_id = r.category_id::integer
);

INSERT INTO core.products (product_id, sku, product_name, category_id, first_listed_on)
SELECT
    r.product_id::integer,
    r.sku,
    r.product_name,
    r.category_id::integer,
    r.first_listed_on::date
FROM reception.products AS r
WHERE NOT EXISTS (
    SELECT 1 FROM quality.rejected_rows AS q
    WHERE q.source_file = 'products.csv' AND q.source_row = r.source_row
);

ALTER TABLE core.order_items
    ADD CONSTRAINT order_items_product_id_fkey
    FOREIGN KEY (product_id) REFERENCES core.products (product_id);

COMMIT;
