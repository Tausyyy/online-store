\set VERBOSITY terse
\echo === RLS: доступ к чужим заказам ===

BEGIN;

DO $$
DECLARE
    c1 BIGINT;
    c2 BIGINT;
    o1 BIGINT;
    o2 BIGINT;
    r  orders%ROWTYPE;
    total_orders BIGINT;
    c1_orders BIGINT;
    n BIGINT;
    own_cart BIGINT;
    foreign_cart BIGINT;
BEGIN
    SELECT customer_id INTO c1 FROM orders GROUP BY customer_id ORDER BY customer_id LIMIT 1;
    SELECT customer_id INTO c2 FROM orders WHERE customer_id <> c1 GROUP BY customer_id ORDER BY customer_id LIMIT 1;
    IF c1 IS NULL OR c2 IS NULL THEN
        RAISE EXCEPTION 'Недостаточно данных: нужны заказы минимум двух покупателей';
    END IF;

    SELECT order_id INTO o1 FROM orders WHERE customer_id = c1 ORDER BY order_id LIMIT 1;
    SELECT order_id INTO o2 FROM orders WHERE customer_id = c2 ORDER BY order_id LIMIT 1;
    SELECT * INTO r FROM orders WHERE order_id = o1;
    SELECT count(*) INTO total_orders FROM orders;
    SELECT count(*) INTO c1_orders FROM orders WHERE customer_id = c1;

    SELECT cart_id INTO own_cart FROM carts WHERE customer_id = c1 ORDER BY cart_id LIMIT 1;
    SELECT cart_id INTO foreign_cart FROM carts WHERE customer_id = c2 ORDER BY cart_id LIMIT 1;

    RAISE NOTICE 'Покупатель A=%, покупатель B=%, чужой заказ=%', c1, c2, o2;

    SET LOCAL ROLE lab4_app;
    PERFORM set_config('app.customer_id', c1::text, true);

    SELECT count(*) INTO n FROM orders;
    IF n <> c1_orders THEN RAISE EXCEPTION 'FAIL: app видит % заказов, ожидается %', n, c1_orders; END IF;
    RAISE NOTICE 'PASS: app (покупатель A) видит только свои заказы: % из % всего', n, total_orders;

    SELECT count(*) INTO n FROM orders WHERE customer_id <> c1;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: app видит чужие заказы (%)', n; END IF;
    RAISE NOTICE 'PASS: чужих заказов в выборке нет';

    SELECT count(*) INTO n FROM orders WHERE order_id = o2;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: чужой заказ % доступен по прямому order_id', o2; END IF;
    RAISE NOTICE 'PASS: SELECT чужого заказа по order_id возвращает 0 строк';

    SELECT count(*) INTO n FROM order_items WHERE order_id = o2;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: app видит позиции чужого заказа (%)', n; END IF;
    RAISE NOTICE 'PASS: позиции чужого заказа не видны';

    SELECT count(*) INTO n FROM order_items WHERE order_id = o1;
    IF n = 0 THEN RAISE NOTICE 'INFO: у заказа % нет позиций, проверка своих позиций пропущена', o1;
    ELSE RAISE NOTICE 'PASS: позиции своего заказа видны (%)', n; END IF;

    IF foreign_cart IS NOT NULL THEN
        SELECT count(*) INTO n FROM carts WHERE cart_id = foreign_cart;
        IF n <> 0 THEN RAISE EXCEPTION 'FAIL: app видит чужую корзину'; END IF;
        SELECT count(*) INTO n FROM cart_items WHERE cart_id = foreign_cart;
        IF n <> 0 THEN RAISE EXCEPTION 'FAIL: app видит позиции чужой корзины'; END IF;
        RAISE NOTICE 'PASS: чужая корзина и её позиции не видны';
    END IF;

    IF own_cart IS NOT NULL THEN
        SELECT count(*) INTO n FROM carts WHERE cart_id = own_cart;
        IF n <> 1 THEN RAISE EXCEPTION 'FAIL: app не видит собственную корзину'; END IF;
        RAISE NOTICE 'PASS: собственная корзина видна';
    END IF;

    UPDATE orders SET status = 'hacked' WHERE order_id = o2;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: UPDATE чужого заказа затронул % строк', n; END IF;
    RAISE NOTICE 'PASS: UPDATE чужого заказа затронул 0 строк';

    DELETE FROM orders WHERE order_id = o2;
    GET DIAGNOSTICS n = ROW_COUNT;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: DELETE чужого заказа затронул % строк', n; END IF;
    RAISE NOTICE 'PASS: DELETE чужого заказа затронул 0 строк';

    BEGIN
        INSERT INTO orders (customer_id, status, customer_name, customer_phone, delivery_method, payment_method)
        VALUES (c2, r.status, r.customer_name, r.customer_phone, r.delivery_method, r.payment_method);
        RAISE EXCEPTION 'FAIL: INSERT заказа от имени чужого покупателя прошёл';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: INSERT заказа от имени чужого покупателя отклонён политикой RLS';
    END;

    BEGIN
        UPDATE orders SET customer_id = c2 WHERE order_id = o1;
        RAISE EXCEPTION 'FAIL: передача своего заказа чужому покупателю прошла';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: смена владельца заказа отклонена политикой RLS';
    END;

    INSERT INTO orders (customer_id, status, customer_name, customer_phone, delivery_method, payment_method)
    VALUES (c1, r.status, r.customer_name, r.customer_phone, r.delivery_method, r.payment_method);
    RAISE NOTICE 'PASS: INSERT собственного заказа разрешён';

    PERFORM set_config('app.customer_id', c2::text, true);
    SELECT count(*) INTO n FROM orders WHERE order_id = o1;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: после смены контекста виден заказ предыдущего покупателя'; END IF;
    SELECT count(*) INTO n FROM orders WHERE order_id = o2;
    IF n <> 1 THEN RAISE EXCEPTION 'FAIL: покупатель B не видит собственный заказ'; END IF;
    RAISE NOTICE 'PASS: при контексте покупателя B виден его заказ и не виден заказ покупателя A';

    PERFORM set_config('app.customer_id', '', true);
    SELECT count(*) INTO n FROM orders;
    IF n <> 0 THEN RAISE EXCEPTION 'FAIL: без контекста покупателя видно % заказов', n; END IF;
    RAISE NOTICE 'PASS: без app.customer_id заказов не видно (доступ закрыт по умолчанию)';

    RESET ROLE;

    SET LOCAL ROLE lab4_analyst;
    SELECT count(*) INTO n FROM orders;
    IF n <> total_orders THEN RAISE EXCEPTION 'FAIL: analyst видит % из % заказов', n, total_orders; END IF;
    RAISE NOTICE 'PASS: analyst читает все заказы для аналитики (%)', n;
    RESET ROLE;

    SET LOCAL ROLE lab4_admin;
    SELECT count(*) INTO n FROM orders;
    IF n < total_orders THEN RAISE EXCEPTION 'FAIL: admin видит % из % заказов', n, total_orders; END IF;
    RAISE NOTICE 'PASS: admin видит все заказы (%)', n;
    RESET ROLE;
END;
$$;

ROLLBACK;

\echo === RLS: политики в базе ===
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced,
       (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid) AS policies
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('orders', 'order_items', 'carts', 'cart_items')
ORDER BY c.relname;
