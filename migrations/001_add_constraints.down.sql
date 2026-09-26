BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001') THEN
        RAISE EXCEPTION 'Миграция 001 не применена — откатывать нечего.';
    END IF;
END $$;

-- ORDER_ITEMS: restore original FK, constraints and types.
ALTER TABLE order_items
    DROP CONSTRAINT fk_order_items_sku,
    ADD CONSTRAINT order_items_sku_id_fkey FOREIGN KEY (sku_id) REFERENCES sku (sku_id),
    DROP CONSTRAINT fk_order_items_order,
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES orders (order_id),
    DROP CONSTRAINT order_items_fixed_price_check,
    ALTER COLUMN fixed_price DROP NOT NULL,
    ALTER COLUMN fixed_price TYPE NUMERIC,
    DROP CONSTRAINT order_items_quantity_check,
    ALTER COLUMN quantity DROP NOT NULL,
    ALTER COLUMN sku_id DROP NOT NULL,
    ALTER COLUMN order_id DROP NOT NULL;

-- ORDERS: restore original FK, nullability, defaults and VARCHAR lengths.
ALTER TABLE orders
    DROP CONSTRAINT fk_orders_customer,
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    ALTER COLUMN created_at DROP DEFAULT,
    ALTER COLUMN created_at DROP NOT NULL,
    ALTER COLUMN payment_method DROP NOT NULL,
    ALTER COLUMN delivery_method DROP NOT NULL,
    ALTER COLUMN customer_phone DROP NOT NULL,
    ALTER COLUMN customer_name DROP NOT NULL,
    ALTER COLUMN customer_name TYPE VARCHAR(200),
    ALTER COLUMN status DROP DEFAULT,
    ALTER COLUMN status DROP NOT NULL,
    ALTER COLUMN customer_id DROP NOT NULL;

-- CART_ITEMS: restore original FK and nullability.
ALTER TABLE cart_items
    DROP CONSTRAINT fk_cart_items_sku,
    ADD CONSTRAINT cart_items_sku_id_fkey FOREIGN KEY (sku_id) REFERENCES sku (sku_id),
    DROP CONSTRAINT fk_cart_items_cart,
    ADD CONSTRAINT cart_items_cart_id_fkey FOREIGN KEY (cart_id) REFERENCES carts (cart_id),
    DROP CONSTRAINT cart_items_quantity_check,
    ALTER COLUMN quantity DROP NOT NULL,
    ALTER COLUMN sku_id DROP NOT NULL,
    ALTER COLUMN cart_id DROP NOT NULL;

-- CARTS: restore original FK, nullability, defaults and status length.
ALTER TABLE carts
    DROP CONSTRAINT fk_carts_customer,
    ADD CONSTRAINT carts_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES customers (customer_id),
    ALTER COLUMN created_at DROP DEFAULT,
    ALTER COLUMN created_at DROP NOT NULL,
    ALTER COLUMN status DROP DEFAULT,
    ALTER COLUMN status DROP NOT NULL,
    ALTER COLUMN status TYPE VARCHAR(50),
    ALTER COLUMN customer_id DROP NOT NULL;

-- SKU: restore original FK, constraints, types and nullability.
ALTER TABLE sku
    DROP CONSTRAINT fk_sku_product,
    ADD CONSTRAINT sku_product_id_fkey FOREIGN KEY (product_id) REFERENCES products (product_id),
    ALTER COLUMN status DROP DEFAULT,
    ALTER COLUMN status DROP NOT NULL,
    ALTER COLUMN status TYPE VARCHAR(50),
    DROP CONSTRAINT sku_stock_quantity_check,
    ALTER COLUMN stock_quantity DROP NOT NULL,
    DROP CONSTRAINT sku_price_check,
    ALTER COLUMN price DROP NOT NULL,
    ALTER COLUMN price TYPE NUMERIC,
    ALTER COLUMN color DROP NOT NULL,
    ALTER COLUMN size DROP NOT NULL,
    ALTER COLUMN size TYPE VARCHAR(50),
    DROP CONSTRAINT sku_article_key,
    ALTER COLUMN article DROP NOT NULL,
    ALTER COLUMN article TYPE VARCHAR(100),
    ALTER COLUMN product_id DROP NOT NULL;

-- PRODUCTS: restore original FK, constraints, defaults and types.
ALTER TABLE products
    DROP CONSTRAINT fk_products_category,
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories (category_id),
    ALTER COLUMN publication_status DROP DEFAULT,
    ALTER COLUMN publication_status DROP NOT NULL,
    ALTER COLUMN publication_status TYPE VARCHAR(50),
    ALTER COLUMN brand TYPE VARCHAR(200),
    ALTER COLUMN name DROP NOT NULL,
    ALTER COLUMN category_id DROP NOT NULL;

-- CUSTOMERS: restore defaults, nullability and original VARCHAR lengths.
ALTER TABLE customers
    ALTER COLUMN role DROP DEFAULT,
    ALTER COLUMN role DROP NOT NULL,
    ALTER COLUMN role TYPE VARCHAR(50),
    ALTER COLUMN password_hash DROP NOT NULL,
    ALTER COLUMN password_hash TYPE VARCHAR(200),
    DROP CONSTRAINT customers_email_key,
    ALTER COLUMN email DROP NOT NULL,
    ALTER COLUMN email TYPE VARCHAR(200);

-- CATEGORIES: restore uniqueness and nullability/type.
ALTER TABLE categories
    DROP CONSTRAINT categories_name_key,
    ALTER COLUMN name DROP NOT NULL,
    ALTER COLUMN name TYPE VARCHAR(200);

DELETE FROM schema_migrations WHERE version = '001';

COMMIT;
