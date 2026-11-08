DO $$
DECLARE
    actual_orders BIGINT;
    actual_items BIGINT;
    actual_revenue NUMERIC;
    actual_sold_products BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO actual_orders
    FROM orders;

    IF actual_orders <> 9 THEN
        RAISE EXCEPTION 'Ожидалось 9 заказов, получено %', actual_orders;
    END IF;

    SELECT COUNT(*)
    INTO actual_items
    FROM order_items;

    IF actual_items <> 14 THEN
        RAISE EXCEPTION 'Ожидалось 14 позиций заказов, получено %', actual_items;
    END IF;

    SELECT COALESCE(SUM(quantity * fixed_price), 0)
    INTO actual_revenue
    FROM order_items;

    IF actual_revenue <> 55980 THEN
        RAISE EXCEPTION 'Ожидалась выручка 55980, получено %', actual_revenue;
    END IF;

    SELECT COUNT(DISTINCT s.product_id)
    INTO actual_sold_products
    FROM order_items oi
    JOIN sku s ON s.sku_id = oi.sku_id;

    IF actual_sold_products <> 2 THEN
        RAISE EXCEPTION 'Ожидалось 2 товара с продажами, получено %', actual_sold_products;
    END IF;

    RAISE NOTICE 'Все проверки пройдены успешно!';
END $$;
