\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_customer_id BIGINT;
    v_sku_id BIGINT;
    v_cart_id BIGINT;
    v_expired_cart_id BIGINT;
    v_locked_cart_id BIGINT;
    v_rows INTEGER;
    v_status TEXT;
BEGIN
    SELECT customer_id
    INTO v_customer_id
    FROM customers
    WHERE email = 'ivan@example.com'
    FOR UPDATE;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Покупатель ivan@example.com не найден';
    END IF;

    SELECT sku_id
    INTO v_sku_id
    FROM sku
    WHERE article = 'TSH-BLK-M'
      AND status = 'on_sale'
    FOR UPDATE;

    IF v_sku_id IS NULL THEN
        RAISE EXCEPTION 'Товар TSH-BLK-M не найден или не продаётся';
    END IF;

    INSERT INTO carts (
        customer_id,
        status,
        created_at,
        expires_at
    )
    VALUES (
        v_customer_id,
        'active',
        now(),
        now() + INTERVAL '7 days'
    )
    RETURNING cart_id INTO v_cart_id;

    SELECT cart_id
    INTO v_locked_cart_id
    FROM carts
    WHERE cart_id = v_cart_id
    FOR UPDATE;

    INSERT INTO cart_items (cart_id, sku_id, quantity)
    VALUES (v_cart_id, v_sku_id, 2);

    UPDATE carts
    SET status = 'completed'
    WHERE cart_id = v_cart_id
      AND status = 'active';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход корзины active -> completed';
    END IF;

    INSERT INTO carts (
        customer_id,
        status,
        created_at,
        expires_at
    )
    VALUES (
        v_customer_id,
        'active',
        now() - INTERVAL '8 days',
        now() - INTERVAL '1 day'
    )
    RETURNING cart_id INTO v_expired_cart_id;

    SELECT cart_id
    INTO v_locked_cart_id
    FROM carts
    WHERE cart_id = v_expired_cart_id
    FOR UPDATE;

    UPDATE carts
    SET status = 'expired'
    WHERE cart_id = v_expired_cart_id
      AND status = 'active'
      AND expires_at < now();

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Корзина не может перейти в expired: статус или срок изменился';
    END IF;

    SELECT status
    INTO v_status
    FROM carts
    WHERE cart_id = v_cart_id;

    RAISE NOTICE 'Корзина ID=%, итоговый статус=%', v_cart_id, v_status;

    SELECT status
    INTO v_status
    FROM carts
    WHERE cart_id = v_expired_cart_id;

    RAISE NOTICE 'Корзина ID=%, итоговый статус=%', v_expired_cart_id, v_status;
END $$;

COMMIT;

SELECT
    c.cart_id,
    c.status,
    cu.email,
    c.created_at,
    c.expires_at,
    s.article,
    ci.quantity
FROM carts c
JOIN customers cu ON cu.customer_id = c.customer_id
LEFT JOIN cart_items ci ON ci.cart_id = c.cart_id
LEFT JOIN sku s ON s.sku_id = ci.sku_id
WHERE cu.email = 'ivan@example.com'
ORDER BY c.cart_id DESC
LIMIT 2;