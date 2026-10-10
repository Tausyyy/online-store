\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_cart_id BIGINT;
    v_customer_id BIGINT;
    v_customer_phone VARCHAR(20);
    v_order_id BIGINT;
    v_item RECORD;
    v_item_count INTEGER := 0;
BEGIN
    -- Находим и блокируем активную корзину Ивана.
    SELECT c.cart_id, c.customer_id, cu.phone
    INTO v_cart_id, v_customer_id, v_customer_phone
    FROM carts c
    JOIN customers cu ON cu.customer_id = c.customer_id
    WHERE cu.email = 'ivan@example.com'
      AND c.status = 'active'
    ORDER BY c.cart_id DESC
    LIMIT 1
    FOR UPDATE OF c;

    IF v_cart_id IS NULL THEN
        RAISE EXCEPTION 'Активная корзина Ивана не найдена';
    END IF;

    -- Блокируем SKU и проверяем возможность покупки.
    FOR v_item IN
        SELECT
            ci.sku_id,
            ci.quantity,
            s.article,
            s.status AS sku_status,
            s.stock_quantity
        FROM cart_items ci
        JOIN sku s ON s.sku_id = ci.sku_id
        WHERE ci.cart_id = v_cart_id
        ORDER BY ci.sku_id
        FOR UPDATE OF s
    LOOP
        v_item_count := v_item_count + 1;

        IF v_item.sku_status IS DISTINCT FROM 'on_sale' THEN
            RAISE EXCEPTION
                'Товар % нельзя купить: статус %',
                v_item.article, v_item.sku_status;
        END IF;

        IF v_item.stock_quantity < v_item.quantity THEN
            RAISE EXCEPTION
                'Недостаточно товара %: требуется %, доступно %',
                v_item.article,
                v_item.quantity,
                v_item.stock_quantity;
        END IF;
    END LOOP;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'Корзина пуста';
    END IF;

    -- Создаём заказ в статусе created.
    INSERT INTO orders (
        customer_id,
        status,
        customer_name,
        customer_phone,
        delivery_method,
        payment_method,
        created_at
    )
    VALUES (
        v_customer_id,
        'created',
        'Иван',
        v_customer_phone,
        'pickup',
        'card',
        CURRENT_TIMESTAMP
    )
    RETURNING order_id INTO v_order_id;

    -- Копируем товары из корзины в заказ по текущей цене.
    INSERT INTO order_items (
        order_id,
        sku_id,
        quantity,
        fixed_price
    )
    SELECT
        v_order_id,
        ci.sku_id,
        ci.quantity,
        s.price
    FROM cart_items ci
    JOIN sku s ON s.sku_id = ci.sku_id
    WHERE ci.cart_id = v_cart_id;

    -- Списываем количество товаров из остатков.
    UPDATE sku s
    SET stock_quantity = s.stock_quantity - ci.quantity
    FROM cart_items ci
    WHERE ci.cart_id = v_cart_id
      AND ci.sku_id = s.sku_id;

    -- Отмечаем корзину как оформленную.
    UPDATE carts
    SET status = 'completed'
    WHERE cart_id = v_cart_id
      AND status = 'active';

    RAISE NOTICE 'Создан заказ %, оформлена корзина %',
        v_order_id, v_cart_id;
END $$;

COMMIT;

-- Проверяем заказ и его позиции.
SELECT
    o.order_id,
    o.status,
    c.email,
    s.article,
    oi.quantity,
    oi.fixed_price
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN sku s ON s.sku_id = oi.sku_id
WHERE c.email = 'ivan@example.com'
ORDER BY o.order_id DESC, s.article
LIMIT 20;

-- Проверяем остатки и статус корзины.
SELECT article, status, stock_quantity
FROM sku
WHERE article IN ('TSH-BLK-M', 'HOD-GRY-M')
ORDER BY article;

SELECT cart_id, status
FROM carts
WHERE cart_id = 1;
