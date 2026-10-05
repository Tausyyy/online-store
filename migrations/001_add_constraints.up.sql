BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version     VARCHAR(20) PRIMARY KEY,
    description TEXT        NOT NULL,
    applied_at  TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001') THEN
        RAISE EXCEPTION 'Миграция 001 уже применена. Повторный запуск отменён.';
    END IF;
END $$;

ALTER TABLE categories
    ALTER COLUMN name TYPE VARCHAR(100),
    ALTER COLUMN name SET NOT NULL,
    ADD CONSTRAINT categories_name_key UNIQUE (name);

ALTER TABLE customers
    ALTER COLUMN email TYPE VARCHAR(255),
    ALTER COLUMN email SET NOT NULL,
    ADD CONSTRAINT customers_email_key UNIQUE (email),
    ALTER COLUMN password_hash TYPE VARCHAR(255),
    ALTER COLUMN password_hash SET NOT NULL,
    ALTER COLUMN role TYPE VARCHAR(30),
    ALTER COLUMN role SET NOT NULL,
    ALTER COLUMN role SET DEFAULT 'customer';

ALTER TABLE products
    ALTER COLUMN category_id SET NOT NULL,
    ALTER COLUMN name SET NOT NULL,
    ALTER COLUMN brand TYPE VARCHAR(100),
    ALTER COLUMN publication_status TYPE VARCHAR(30),
    ALTER COLUMN publication_status SET NOT NULL,
    ALTER COLUMN publication_status SET DEFAULT 'draft';

ALTER TABLE products
    DROP CONSTRAINT products_category_id_fkey,
    ADD CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES categories (category_id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE sku
    ALTER COLUMN product_id SET NOT NULL,
    ALTER COLUMN article TYPE VARCHAR(50),
    ALTER COLUMN article SET NOT NULL,
    ADD CONSTRAINT sku_article_key UNIQUE (article),
    ALTER COLUMN size TYPE VARCHAR(20),
    ALTER COLUMN size SET NOT NULL,
    ALTER COLUMN color SET NOT NULL,
    ALTER COLUMN price TYPE NUMERIC(10, 2),
    ALTER COLUMN price SET NOT NULL,
    ADD CONSTRAINT sku_price_check CHECK (price >= 0),
    ALTER COLUMN stock_quantity SET NOT NULL,
    ADD CONSTRAINT sku_stock_quantity_check CHECK (stock_quantity >= 0),
    ALTER COLUMN status TYPE VARCHAR(30),
    ALTER COLUMN status SET NOT NULL,
    ALTER COLUMN status SET DEFAULT 'draft';

ALTER TABLE sku
    DROP CONSTRAINT sku_product_id_fkey,
    ADD CONSTRAINT fk_sku_product
        FOREIGN KEY (product_id) REFERENCES products (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE carts
    ALTER COLUMN customer_id SET NOT NULL,
    ALTER COLUMN status TYPE VARCHAR(30),
    ALTER COLUMN status SET NOT NULL,
    ALTER COLUMN status SET DEFAULT 'active',
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE carts
    DROP CONSTRAINT carts_customer_id_fkey,
    ADD CONSTRAINT fk_carts_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE cart_items
    ALTER COLUMN cart_id SET NOT NULL,
    ALTER COLUMN sku_id SET NOT NULL,
    ALTER COLUMN quantity SET NOT NULL,
    ADD CONSTRAINT cart_items_quantity_check CHECK (quantity > 0);

ALTER TABLE cart_items
    DROP CONSTRAINT cart_items_cart_id_fkey,
    ADD CONSTRAINT fk_cart_items_cart
        FOREIGN KEY (cart_id) REFERENCES carts (cart_id)
        ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE cart_items
    DROP CONSTRAINT cart_items_sku_id_fkey,
    ADD CONSTRAINT fk_cart_items_sku
        FOREIGN KEY (sku_id) REFERENCES sku (sku_id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

UPDATE orders
SET created_at = CURRENT_TIMESTAMP
WHERE created_at IS NULL;

ALTER TABLE orders
    ALTER COLUMN customer_id SET NOT NULL,
    ALTER COLUMN status TYPE VARCHAR(50),
    ALTER COLUMN status SET NOT NULL,
    ALTER COLUMN status SET DEFAULT 'created',
    ALTER COLUMN customer_name TYPE VARCHAR(100),
    ALTER COLUMN customer_name SET NOT NULL,
    ALTER COLUMN customer_phone SET NOT NULL,
    ALTER COLUMN delivery_method SET NOT NULL,
    ALTER COLUMN payment_method SET NOT NULL,
    ALTER COLUMN created_at SET NOT NULL,
    ALTER COLUMN created_at SET DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE orders
    DROP CONSTRAINT orders_customer_id_fkey,
    ADD CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE order_items
    ALTER COLUMN order_id SET NOT NULL,
    ALTER COLUMN sku_id SET NOT NULL,
    ALTER COLUMN quantity SET NOT NULL,
    ADD CONSTRAINT order_items_quantity_check CHECK (quantity > 0),
    ALTER COLUMN fixed_price TYPE NUMERIC(10, 2),
    ALTER COLUMN fixed_price SET NOT NULL,
    ADD CONSTRAINT order_items_fixed_price_check CHECK (fixed_price >= 0);

ALTER TABLE order_items
    DROP CONSTRAINT order_items_order_id_fkey,
    ADD CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES orders (order_id)
        ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE order_items
    DROP CONSTRAINT order_items_sku_id_fkey,
    ADD CONSTRAINT fk_order_items_sku
        FOREIGN KEY (sku_id) REFERENCES sku (sku_id)
        ON DELETE RESTRICT ON UPDATE CASCADE;

INSERT INTO schema_migrations (version, description)
VALUES ('001', 'NOT NULL, UNIQUE, CHECK, типы данных, ON DELETE/UPDATE для FK');

COMMIT;
