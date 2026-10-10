-- ЛР-3, роль 3: многошаговая транзакция с успешным COMMIT.
-- Запускать на тестовой БД после создания таблиц, загрузки data.sql и UP-миграции.

BEGIN;

DO $$
DECLARE
    v_customer_id BIGINT;
    v_sku_id BIGINT;
    v_price NUMERIC(10, 2);
    v_stock INTEGER;
    v_order_id BIGINT;
    v_quantity INTEGER := 2;
BEGIN
    SELECT customer_id INTO v_customer_id
    FROM customers
    WHERE email = 'anna@example.com';

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Не найден покупатель anna@example.com';
    END IF;

    SELECT sku_id, price, stock_quantity
    INTO v_sku_id, v_price, v_stock
    FROM sku
    WHERE article = 'TSH-BLK-M'
    FOR UPDATE;

    IF v_sku_id IS NULL THEN
        RAISE EXCEPTION 'Не найден SKU TSH-BLK-M';
    END IF;

    IF v_stock < v_quantity THEN
        RAISE EXCEPTION 'Недостаточно товара: нужно %, доступно %', v_quantity, v_stock;
    END IF;

    INSERT INTO orders (
        customer_id, status, customer_name, customer_phone,
        delivery_method, payment_method, created_at
    )
    SELECT c.customer_id, 'awaiting_payment', 'Демонстрационный заказ',
           c.phone, 'pickup', 'card', CURRENT_TIMESTAMP
    FROM customers c
    WHERE c.customer_id = v_customer_id
    RETURNING order_id INTO v_order_id;

    INSERT INTO order_items (order_id, sku_id, quantity, fixed_price)
    VALUES (v_order_id, v_sku_id, v_quantity, v_price);

    UPDATE sku
    SET stock_quantity = stock_quantity - v_quantity
    WHERE sku_id = v_sku_id;

    RAISE NOTICE 'Создан заказ %, списано единиц: %', v_order_id, v_quantity;
END $$;

COMMIT;

SELECT o.order_id, o.status, c.email, oi.quantity, oi.fixed_price, s.article
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN sku s ON s.sku_id = oi.sku_id
WHERE c.email = 'anna@example.com'
ORDER BY o.order_id DESC
LIMIT 1;

SELECT article, stock_quantity
FROM sku
WHERE article = 'TSH-BLK-M';
