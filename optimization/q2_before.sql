-- Запрос 2 из роли 2 (queries/business_queries.sql): самые продаваемые товары среди доставленных заказов.
-- Исходный вариант, без изменений.
SELECT
    p.product_id,
    p.name AS product_name,
    SUM(oi.quantity) AS total_sold
FROM products p
JOIN sku s ON p.product_id = s.product_id
JOIN order_items oi ON s.sku_id = oi.sku_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'delivered'
GROUP BY p.product_id, p.name
ORDER BY total_sold DESC
LIMIT 10;
