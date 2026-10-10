-- ЛР-3, роль 3: контролируемый ROLLBACK.
-- Временные изменения заказа, позиции и остатка отменяются в конце.

SELECT 'BEFORE' AS stage, stock_quantity
FROM sku WHERE article = 'TSH-BLK-M';

SELECT 'BEFORE' AS stage, COUNT(*) AS anna_orders
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE c.email = 'anna@example.com';

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
    FROM customers WHERE email = 'anna@example.com';

    SELECT sku_id, price, stock_quantity
    INTO v_sku_id, v_price, v_stock
    FROM sku
    WHERE article = 'TSH-BLK-M'
    FOR UPDATE;

    IF v_customer_id IS NULL OR v_sku_id IS NULL THEN
        RAISE EXCEPTION 'Не найдены покупатель или SKU для демонстрации';
    END IF;

    IF v_stock < v_quantity THEN
        RAISE EXCEPTION 'Недостаточно товара: нужно %, доступно %', v_quantity, v_stock;
    END IF;

    INSERT INTO orders (
        customer_id, status, customer_name, customer_phone,
        delivery_method, payment_method, created_at
    )
    SELECT c.customer_id, 'awaiting_payment', 'ROLLBACK demo',
           c.phone, 'pickup', 'card', CURRENT_TIMESTAMP
    FROM customers c
    WHERE c.customer_id = v_customer_id
    RETURNING order_id INTO v_order_id;

    INSERT INTO order_items (order_id, sku_id, quantity, fixed_price)
    VALUES (v_order_id, v_sku_id, v_quantity, v_price);

    UPDATE sku
    SET stock_quantity = stock_quantity - v_quantity
    WHERE sku_id = v_sku_id;

    RAISE NOTICE 'Внутри транзакции временно создан заказ %, остаток уменьшен', v_order_id;
END $$;

ROLLBACK;

SELECT 'AFTER ROLLBACK' AS stage, stock_quantity
FROM sku WHERE article = 'TSH-BLK-M';

SELECT 'AFTER ROLLBACK' AS stage, COUNT(*) AS anna_orders
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE c.email = 'anna@example.com';
