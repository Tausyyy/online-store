\echo '=== 1. Сколько строк в таблицах'
SELECT 'categories' AS table_name, count(*) AS rows FROM categories
UNION ALL SELECT 'customers',   count(*) FROM customers
UNION ALL SELECT 'products',    count(*) FROM products
UNION ALL SELECT 'sku',         count(*) FROM sku
UNION ALL SELECT 'carts',       count(*) FROM carts
UNION ALL SELECT 'cart_items',  count(*) FROM cart_items
UNION ALL SELECT 'orders',      count(*) FROM orders
UNION ALL SELECT 'order_items', count(*) FROM order_items;

\echo '=== 2. Заказы по статусам (доля в процентах)'
SELECT status,
       count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS percent
FROM orders
GROUP BY status
ORDER BY orders DESC;

\echo '=== 3. Неравномерность: топ-5 покупателей по числу заказов'
SELECT customer_id, count(*) AS orders
FROM orders
GROUP BY customer_id
ORDER BY orders DESC
LIMIT 5;

\echo '=== 3b. Для сравнения: среднее число заказов на покупателя'
SELECT round(count(*)::numeric / count(DISTINCT customer_id), 1) AS avg_orders_per_customer
FROM orders;

\echo '=== 4. Даты заказов: самый старый и самый новый'
SELECT min(created_at) AS first_order, max(created_at) AS last_order FROM orders;

\echo '=== 5. Товары и SKU по статусам'
SELECT 'product' AS kind, publication_status AS status, count(*) FROM products GROUP BY publication_status
UNION ALL
SELECT 'sku', status, count(*) FROM sku GROUP BY status
ORDER BY kind, count DESC;

\echo '=== 6. Бизнес-ограничения (ожидается 0 во всех строках)'
SELECT 'sku с отрицательным остатком' AS check_name, count(*) AS bad FROM sku WHERE stock_quantity < 0
UNION ALL SELECT 'sku с отрицательной ценой', count(*) FROM sku WHERE price < 0
UNION ALL SELECT 'позиции заказа с количеством <= 0', count(*) FROM order_items WHERE quantity <= 0
UNION ALL SELECT 'позиции корзины с количеством <= 0', count(*) FROM cart_items WHERE quantity <= 0
UNION ALL SELECT 'заказы без позиций', count(*) FROM orders o
          WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.order_id);

\echo '=== 7. Отпечаток сгенерированных данных (у двух запусков с одним seed должен совпасть)'
SELECT count(*) AS items, sum(oi.quantity) AS total_quantity, sum(oi.fixed_price) AS total_price
FROM order_items oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.customer_name ~ '^g[a-zA-Z0-9]+_order_[0-9]+$';

\echo '=== 8. Сверка бизнес-запросов с независимым подсчётом'
\echo '--- Q1 (customer_id = 15): число строк запроса и контрольный подсчёт (должны совпасть)'
SELECT
  (SELECT count(*)
     FROM customers c
     JOIN orders o       ON c.customer_id = o.customer_id
     JOIN order_items oi ON o.order_id = oi.order_id
     JOIN sku s          ON oi.sku_id = s.sku_id
     JOIN products p     ON s.product_id = p.product_id
    WHERE c.customer_id = 15) AS rows_in_query,
  (SELECT count(*) FROM order_items
    WHERE order_id IN (SELECT order_id FROM orders WHERE customer_id = 15)) AS control_count;

\echo '--- Q4 (>= 5 заказов): число клиентов в запросе и контрольный подсчёт (должны совпасть)'
SELECT
  (SELECT count(*) FROM (
      SELECT c.customer_id
      FROM customers c JOIN orders o ON c.customer_id = o.customer_id
      GROUP BY c.customer_id, c.email
      HAVING COUNT(o.order_id) >= 5) q) AS rows_in_query,
  (SELECT count(*) FROM (
      SELECT customer_id FROM orders GROUP BY customer_id HAVING count(*) >= 5) q) AS control_count;

\echo '--- Q3: сумма выручки по категориям (только доставленные) и контрольная сумма (должны совпасть)'
SELECT
  (SELECT sum(revenue) FROM (
      SELECT sum(oi.quantity * oi.fixed_price) AS revenue
      FROM categories c
      JOIN products p ON c.category_id = p.category_id
      JOIN sku s ON p.product_id = s.product_id
      JOIN order_items oi ON s.sku_id = oi.sku_id
      JOIN orders o ON oi.order_id = o.order_id
      WHERE o.status = 'delivered'
      GROUP BY c.name) q) AS sum_by_categories,
  (SELECT sum(oi.quantity * oi.fixed_price)
     FROM order_items oi JOIN orders o ON o.order_id = oi.order_id
    WHERE o.status = 'delivered') AS control_sum;
