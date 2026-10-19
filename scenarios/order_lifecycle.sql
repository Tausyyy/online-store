\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_customer_id BIGINT;
    v_sku_id BIGINT;
    v_order_id BIGINT;
    v_locked_order_id BIGINT;
    v_required_quantity INTEGER := 2;
    v_available_quantity INTEGER;
    v_rows INTEGER;
    v_status TEXT;
BEGIN
    SELECT customer_id
    INTO v_customer_id
    FROM customers
    WHERE email = 'anna@example.com'
    FOR UPDATE;

    IF v_customer_id IS NULL THEN
        RAISE EXCEPTION 'Покупатель anna@example.com не найден';
    END IF;

    SELECT sku_id, stock_quantity
    INTO v_sku_id, v_available_quantity
    FROM sku
    WHERE article = 'TSH-WHT-L'
      AND status = 'on_sale'
    FOR UPDATE;

    IF v_sku_id IS NULL THEN
        RAISE EXCEPTION 'Товар TSH-WHT-L не найден или не продаётся';
    END IF;

    IF v_available_quantity < v_required_quantity THEN
        RAISE EXCEPTION 'Недостаточно товара: требуется %, доступно %',
            v_required_quantity, v_available_quantity;
    END IF;

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
        'Anna Example',
        '+70000000000',
        'courier',
        'card',
        now()
    )
    RETURNING order_id INTO v_order_id;

    SELECT order_id
    INTO v_locked_order_id
    FROM orders
    WHERE order_id = v_order_id
    FOR UPDATE;

    INSERT INTO order_items (
        order_id,
        sku_id,
        quantity,
        fixed_price
    )
    SELECT
        v_order_id,
        v_sku_id,
        v_required_quantity,
        price
    FROM sku
    WHERE sku_id = v_sku_id;

    UPDATE sku
    SET stock_quantity = stock_quantity - v_required_quantity,
        status = CASE
            WHEN stock_quantity - v_required_quantity = 0
                THEN 'out_of_stock'
            ELSE status
        END
    WHERE sku_id = v_sku_id
      AND status = 'on_sale'
      AND stock_quantity >= v_required_quantity;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Не удалось списать товар: остаток или статус изменился';
    END IF;

    UPDATE orders
    SET status = 'awaiting_payment'
    WHERE order_id = v_order_id
      AND status = 'created';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход заказа created -> awaiting_payment';
    END IF;

    UPDATE orders
    SET status = 'paid'
    WHERE order_id = v_order_id
      AND status = 'awaiting_payment';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход заказа awaiting_payment -> paid';
    END IF;

    UPDATE orders
    SET status = 'in_assembly'
    WHERE order_id = v_order_id
      AND status = 'paid';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход заказа paid -> in_assembly';
    END IF;

    UPDATE orders
    SET status = 'handed_to_delivery'
    WHERE order_id = v_order_id
      AND status = 'in_assembly';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход заказа in_assembly -> handed_to_delivery';
    END IF;

    UPDATE orders
    SET status = 'delivered'
    WHERE order_id = v_order_id
      AND status = 'handed_to_delivery';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход заказа handed_to_delivery -> delivered';
    END IF;

    UPDATE orders
    SET status = 'return_processed'
    WHERE order_id = v_order_id
      AND status = 'delivered';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход заказа delivered -> return_processed';
    END IF;

    SELECT status
    INTO v_status
    FROM orders
    WHERE order_id = v_order_id;

    RAISE NOTICE 'Заказ ID=%, итоговый статус=%', v_order_id, v_status;
END $$;

COMMIT;

SELECT
    o.order_id,
    o.status,
    c.email,
    oi.quantity,
    oi.fixed_price,
    s.article,
    s.stock_quantity
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
JOIN sku s ON s.sku_id = oi.sku_id
WHERE c.email = 'anna@example.com'
ORDER BY o.order_id DESC
LIMIT 1;