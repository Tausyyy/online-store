-- Проверка итоговой схемы после UP.
BEGIN;

DO $$
DECLARE
    v_count integer;
BEGIN
    SELECT count(*) INTO v_count
    FROM information_schema.columns
    WHERE table_name = 'categories' AND column_name = 'name'
      AND is_nullable = 'NO' AND character_maximum_length = 100;
    IF v_count <> 1 THEN RAISE EXCEPTION 'categories.name: ожидался NOT NULL VARCHAR(100)'; END IF;

    SELECT count(*) INTO v_count
    FROM information_schema.columns
    WHERE table_name = 'customers' AND column_name = 'email'
      AND is_nullable = 'NO' AND character_maximum_length = 255;
    IF v_count <> 1 THEN RAISE EXCEPTION 'customers.email: ожидался NOT NULL VARCHAR(255)'; END IF;

    SELECT count(*) INTO v_count
    FROM information_schema.columns
    WHERE table_name = 'sku' AND column_name = 'price'
      AND is_nullable = 'NO' AND numeric_precision = 10 AND numeric_scale = 2;
    IF v_count <> 1 THEN RAISE EXCEPTION 'sku.price: ожидался NOT NULL NUMERIC(10,2)'; END IF;

    SELECT count(*) INTO v_count
    FROM information_schema.columns
    WHERE table_name = 'orders' AND column_name = 'created_at'
      AND is_nullable = 'NO';
    IF v_count <> 1 THEN RAISE EXCEPTION 'orders.created_at: ожидался NOT NULL'; END IF;

    SELECT count(*) INTO v_count
    FROM pg_constraint
    WHERE conname IN (
        'categories_name_key', 'customers_email_key', 'sku_article_key',
        'sku_price_check', 'sku_stock_quantity_check',
        'cart_items_quantity_check', 'order_items_quantity_check',
        'order_items_fixed_price_check'
    );
    IF v_count <> 8 THEN
        RAISE EXCEPTION 'Ожидалось 8 ключевых UNIQUE/CHECK ограничений, найдено %', v_count;
    END IF;

    SELECT count(*) INTO v_count
    FROM pg_constraint
    WHERE conname IN (
        'fk_products_category', 'fk_sku_product', 'fk_carts_customer',
        'fk_cart_items_cart', 'fk_cart_items_sku',
        'fk_orders_customer', 'fk_order_items_order', 'fk_order_items_sku'
    );
    IF v_count <> 8 THEN
        RAISE EXCEPTION 'Ожидалось 8 заменённых FK, найдено %', v_count;
    END IF;
END $$;

ROLLBACK;
