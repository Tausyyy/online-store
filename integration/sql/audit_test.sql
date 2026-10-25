\set VERBOSITY terse
\echo === Аудит критических операций ===

BEGIN;

DO $$
DECLARE
    c1 BIGINT;
    s1 BIGINT;
    new_order BIGINT;
    new_item BIGINT;
    n0 BIGINT;
    n1 BIGINT;
    rec audit_log%ROWTYPE;
    old_price NUMERIC;
    old_hash TEXT;
    base BIGINT;
BEGIN
    SELECT COALESCE(max(audit_id), 0) INTO base FROM audit_log;
    SELECT customer_id INTO c1 FROM customers ORDER BY customer_id LIMIT 1;
    SELECT sku_id, price INTO s1, old_price FROM sku ORDER BY sku_id LIMIT 1;
    IF c1 IS NULL OR s1 IS NULL THEN
        RAISE EXCEPTION 'Недостаточно данных: нужны покупатель и SKU';
    END IF;

    INSERT INTO orders (customer_id, status, customer_name, customer_phone, delivery_method, payment_method)
    VALUES (c1, 'created', 'Audit Test', '+70000000000', 'courier', 'card')
    RETURNING order_id INTO new_order;

    SELECT * INTO rec FROM audit_log
     WHERE audit_id > base AND table_name = 'orders' AND operation = 'INSERT' AND row_pk = new_order::text;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: создание заказа не попало в аудит'; END IF;
    RAISE NOTICE 'PASS: INSERT заказа записан в аудит (db_user=%)', rec.db_user;

    INSERT INTO order_items (order_id, sku_id, quantity, fixed_price)
    VALUES (new_order, s1, 1, old_price)
    RETURNING order_item_id INTO new_item;

    SELECT count(*) INTO n0 FROM audit_log;
    UPDATE orders SET status = status WHERE order_id = new_order;
    SELECT count(*) INTO n1 FROM audit_log;
    IF n1 <> n0 THEN RAISE EXCEPTION 'FAIL: UPDATE без изменений попал в аудит'; END IF;
    RAISE NOTICE 'PASS: UPDATE без реального изменения не создаёт записей';

    UPDATE orders SET status = 'paid' WHERE order_id = new_order;
    SELECT * INTO rec FROM audit_log
     WHERE audit_id > base AND table_name = 'orders' AND operation = 'UPDATE' AND row_pk = new_order::text
     ORDER BY audit_id DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: смена статуса заказа не попала в аудит'; END IF;
    IF rec.changed_columns <> ARRAY['status'] OR rec.old_data ->> 'status' <> 'created' OR rec.new_data ->> 'status' <> 'paid' THEN
        RAISE EXCEPTION 'FAIL: неверное содержимое записи аудита: %', rec;
    END IF;
    RAISE NOTICE 'PASS: смена статуса created -> paid записана, изменённые поля: %', rec.changed_columns;

    UPDATE sku SET stock_quantity = stock_quantity WHERE sku_id = s1;
    UPDATE sku SET stock_quantity = stock_quantity + 1 WHERE sku_id = s1;
    SELECT count(*) INTO n1 FROM audit_log WHERE audit_id > base AND table_name = 'sku' AND row_pk = s1::text;
    IF n1 <> 0 THEN RAISE EXCEPTION 'FAIL: изменение остатка попало в аудит'; END IF;
    RAISE NOTICE 'PASS: изменение остатка SKU не аудируется';

    UPDATE sku SET price = price + 1 WHERE sku_id = s1;
    SELECT * INTO rec FROM audit_log WHERE audit_id > base AND table_name = 'sku' AND operation = 'UPDATE' AND row_pk = s1::text;
    IF NOT FOUND OR rec.changed_columns <> ARRAY['price'] THEN RAISE EXCEPTION 'FAIL: изменение цены не попало в аудит'; END IF;
    RAISE NOTICE 'PASS: изменение цены SKU записано (% -> %)', rec.old_data ->> 'price', rec.new_data ->> 'price';

    SELECT password_hash INTO old_hash FROM customers WHERE customer_id = c1;
    UPDATE customers SET password_hash = 'audit_test_new_hash' WHERE customer_id = c1;
    SELECT * INTO rec FROM audit_log WHERE audit_id > base AND table_name = 'customers' AND operation = 'UPDATE' AND row_pk = c1::text ORDER BY audit_id DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: смена пароля не попала в аудит'; END IF;
    IF rec.old_data ? 'password_hash' OR rec.new_data ? 'password_hash' OR rec::text LIKE '%audit_test_new_hash%' OR rec::text LIKE '%' || old_hash || '%' THEN
        RAISE EXCEPTION 'FAIL: хеш пароля попал в аудит';
    END IF;
    IF NOT ('password_hash' = ANY (rec.changed_columns)) THEN RAISE EXCEPTION 'FAIL: факт смены пароля не отмечен'; END IF;
    RAISE NOTICE 'PASS: смена пароля записана без значений хешей, изменённые поля: %', rec.changed_columns;

    UPDATE customers SET role = 'admin' WHERE customer_id = c1;
    SELECT count(*) INTO n1 FROM audit_log WHERE audit_id > base AND table_name = 'customers' AND row_pk = c1::text AND changed_columns @> ARRAY['role'];
    IF n1 <> 1 THEN RAISE EXCEPTION 'FAIL: смена роли покупателя не попала в аудит'; END IF;
    RAISE NOTICE 'PASS: смена роли покупателя записана';

    DELETE FROM orders WHERE order_id = new_order;
    SELECT count(*) INTO n1 FROM audit_log WHERE audit_id > base AND table_name = 'orders' AND operation = 'DELETE' AND row_pk = new_order::text;
    IF n1 <> 1 THEN RAISE EXCEPTION 'FAIL: удаление заказа не попало в аудит'; END IF;
    SELECT count(*) INTO n1 FROM audit_log WHERE audit_id > base AND table_name = 'order_items' AND operation = 'DELETE' AND row_pk = new_item::text;
    IF n1 <> 1 THEN RAISE EXCEPTION 'FAIL: каскадное удаление позиции не попало в аудит'; END IF;
    RAISE NOTICE 'PASS: удаление заказа и каскадное удаление позиции записаны';
END;
$$;

DO $$
DECLARE
    c1 BIGINT;
    o1 BIGINT;
    rec audit_log%ROWTYPE;
    base BIGINT;
BEGIN
    SELECT COALESCE(max(audit_id), 0) INTO base FROM audit_log;
    SELECT customer_id, order_id INTO c1, o1 FROM orders ORDER BY order_id LIMIT 1;

    SET LOCAL ROLE lab4_app;
    PERFORM set_config('app.customer_id', c1::text, true);
    UPDATE orders SET status = 'audit_by_app' WHERE order_id = o1;
    RESET ROLE;

    SELECT * INTO rec FROM audit_log
     WHERE audit_id > base AND table_name = 'orders' AND operation = 'UPDATE' AND row_pk = o1::text AND new_data ->> 'status' = 'audit_by_app';
    IF NOT FOUND THEN RAISE EXCEPTION 'FAIL: действие приложения не попало в аудит'; END IF;
    IF rec.db_user <> 'lab4_app' OR rec.app_customer_id <> c1::text THEN
        RAISE EXCEPTION 'FAIL: в аудите неверный исполнитель: db_user=%, app_customer_id=%', rec.db_user, rec.app_customer_id;
    END IF;
    RAISE NOTICE 'PASS: аудит фиксирует роль (%) и покупателя (%) из контекста приложения', rec.db_user, rec.app_customer_id;
END;
$$;

DO $$
DECLARE
    n BIGINT;
BEGIN
    SET LOCAL ROLE lab4_app;
    BEGIN
        PERFORM count(*) FROM audit_log;
        RAISE EXCEPTION 'FAIL: app прочитал audit_log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: app не может читать audit_log';
    END;
    BEGIN
        INSERT INTO audit_log (db_user, table_name, operation) VALUES ('forged', 'orders', 'INSERT');
        RAISE EXCEPTION 'FAIL: app записал строку в audit_log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: app не может писать в audit_log напрямую';
    END;
    RESET ROLE;

    SET LOCAL ROLE lab4_analyst;
    BEGIN
        PERFORM count(*) FROM audit_log;
        RAISE EXCEPTION 'FAIL: analyst прочитал audit_log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: analyst не может читать audit_log';
    END;
    RESET ROLE;

    SET LOCAL ROLE lab4_admin;
    SELECT count(*) INTO n FROM audit_log;
    RAISE NOTICE 'PASS: admin читает audit_log (записей в транзакции: %)', n;
    BEGIN
        UPDATE audit_log SET operation = 'X';
        RAISE EXCEPTION 'FAIL: admin изменил audit_log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: admin не может изменять audit_log';
    END;
    BEGIN
        DELETE FROM audit_log;
        RAISE EXCEPTION 'FAIL: admin удалил записи audit_log';
    EXCEPTION WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: admin не может удалять записи audit_log';
    END;
    RESET ROLE;
END;
$$;

DO $$
BEGIN
    BEGIN
        UPDATE audit_log SET operation = 'X';
        RAISE EXCEPTION 'FAIL: суперпользователь изменил audit_log';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: триггер блокирует UPDATE даже для суперпользователя';
    END;
    BEGIN
        DELETE FROM audit_log;
        RAISE EXCEPTION 'FAIL: суперпользователь удалил записи audit_log';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: триггер блокирует DELETE даже для суперпользователя';
    END;
    BEGIN
        TRUNCATE audit_log;
        RAISE EXCEPTION 'FAIL: суперпользователь очистил audit_log';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: триггер блокирует TRUNCATE даже для суперпользователя';
    END;
END;
$$;

ROLLBACK;

\echo === Аудит: последние записи в базе (после отката теста остаются только реальные операции) ===
SELECT audit_id, occurred_at, db_user, table_name, operation, row_pk
FROM audit_log
ORDER BY audit_id DESC
LIMIT 10;
