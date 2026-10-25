\set VERBOSITY terse
\echo === Реальные операции для журнала аудита ===

SELECT customer_id AS demo_customer FROM orders ORDER BY order_id LIMIT 1 \gset

BEGIN;
SET LOCAL ROLE lab4_app;
SELECT set_config('app.customer_id', :'demo_customer', true) \gset
INSERT INTO orders (customer_id, status, customer_name, customer_phone, delivery_method, payment_method)
SELECT customer_id, 'created', customer_name, customer_phone, delivery_method, payment_method
FROM orders
WHERE customer_id = :demo_customer
ORDER BY order_id
LIMIT 1;
UPDATE orders
SET status = 'paid'
WHERE order_id = (SELECT max(order_id) FROM orders WHERE customer_id = :demo_customer);
COMMIT;

BEGIN;
SET LOCAL ROLE lab4_admin;
UPDATE sku SET price = price + 1 WHERE sku_id = (SELECT min(sku_id) FROM sku);
UPDATE sku SET price = price - 1 WHERE sku_id = (SELECT min(sku_id) FROM sku);
COMMIT;

\echo === Журнал аудита (читает lab4_admin) ===
BEGIN;
SET LOCAL ROLE lab4_admin;
SELECT audit_id, db_user, app_customer_id, table_name, operation, row_pk, changed_columns
FROM audit_log
ORDER BY audit_id;
COMMIT;
