\set ON_ERROR_STOP on

-- Сохраняем исходное состояние для сравнения.
SELECT
    (SELECT COUNT(*) FROM orders) AS orders_before,
    (SELECT COUNT(*) FROM order_items) AS items_before,
    (SELECT stock_quantity FROM sku WHERE article = 'TSH-BLK-M') AS tshirt_stock_before,
    (SELECT stock_quantity FROM sku WHERE article = 'HOD-GRY-M') AS hoodie_stock_before
\gset

BEGIN;

DO $$
DECLARE
    v_customer_id BIGINT;
    v_cart_id BIGINT;
    v_order_id BIGINT;
    v_phone VARCHAR(20);
BEGIN
    SELECT customer_id, phone
    INTO v_customer_id, v_phone
    FROM customers
    WHERE email = 'ivan@example.com';

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Покупатель ivan@example.com не найден';
    END IF;

    -- Создаём временную корзину внутри транзакции.
    INSERT INTO carts (customer_id, status, created_at)
    VALUES (v_customer_id, 'active', CURRENT_TIMESTAMP)
    RETURNING cart_id INTO v_cart_id;

    -- Добавляем тестовые товары.
    INSERT INTO cart_items (cart_id, sku_id, quantity)
    SELECT v_cart_id, sku_id, 1
    FROM sku
    WHERE article = 'TSH-BLK-M'
      AND status = 'on_sale'
      AND stock_quantity >= 1;

    IF NOT EXISTS (
        SELECT 1 FROM cart_items WHERE cart_id = v_cart_id
    ) THEN
        RAISE EXCEPTION 'Нет доступной футболки для теста';
    END IF;

    -- Блокируем товары и проверяем остатки и статус.
    PERFORM s.sku_id
    FROM sku s
    JOIN cart_items ci ON ci.sku_id = s.sku_id
    WHERE ci.cart_id = v_cart_id
      AND s.status = 'on_sale'
      AND s.stock_quantity >= ci.quantity
    FOR UPDATE OF s;

    IF EXISTS (
        SELECT 1
        FROM cart_items ci
        JOIN sku s ON s.sku_id = ci.sku_id
        WHERE ci.cart_id = v_cart_id
          AND (s.status <> 'on_sale' OR s.stock_quantity < ci.quantity)
    ) THEN
        RAISE EXCEPTION 'Проверка товара или остатка не пройдена';
    END IF;

    -- Создаём временный заказ со статусом created.
    INSERT INTO orders (
        customer_id, status, customer_name, customer_phone,
        delivery_method, payment_method, created_at
    )
    VALUES (
        v_customer_id, 'created', 'Иван',
        v_phone, 'pickup', 'card', CURRENT_TIMESTAMP
    )
    RETURNING order_id INTO v_order_id;

    -- Добавляем позицию заказа.
    INSERT INTO order_items (order_id, sku_id, quantity, fixed_price)
    SELECT v_order_id, ci.sku_id, ci.quantity, s.price
    FROM cart_items ci
    JOIN sku s ON s.sku_id = ci.sku_id
    WHERE ci.cart_id = v_cart_id;

    -- Списываем товар и закрываем корзину.
    UPDATE sku s
    SET stock_quantity = s.stock_quantity - ci.quantity
    FROM cart_items ci
    WHERE ci.cart_id = v_cart_id
      AND ci.sku_id = s.sku_id;

    UPDATE carts
    SET status = 'completed'
    WHERE cart_id = v_cart_id;

    RAISE NOTICE
        'Внутри транзакции создан заказ %, остаток временно уменьшен',
        v_order_id;
END $$;

-- Отменяем создание корзины, заказа, позиции и списание товара.
ROLLBACK;

-- Сравниваем состояние после отката с исходным.
SELECT
    (SELECT COUNT(*) FROM orders) AS orders_after,
    (SELECT COUNT(*) FROM order_items) AS items_after,
    (SELECT stock_quantity FROM sku WHERE article = 'TSH-BLK-M') AS tshirt_stock_after,
    (SELECT stock_quantity FROM sku WHERE article = 'HOD-GRY-M') AS hoodie_stock_after
\gset

SELECT
    :orders_before AS orders_before,
    :orders_after AS orders_after,
    :items_before AS items_before,
    :items_after AS items_after,
    :tshirt_stock_before AS tshirt_stock_before,
    :tshirt_stock_after AS tshirt_stock_after,
    :hoodie_stock_before AS hoodie_stock_before,
    :hoodie_stock_after AS hoodie_stock_after;
