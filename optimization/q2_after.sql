SELECT
    p.product_id,
    p.name AS product_name,
    SUM(t.sold) AS total_sold
FROM (
    SELECT oi.sku_id, SUM(oi.quantity) AS sold
    FROM order_items oi
    JOIN orders o ON oi.order_id = o.order_id
    WHERE o.status = 'delivered'
    GROUP BY oi.sku_id
) AS t
JOIN sku s ON s.sku_id = t.sku_id
JOIN products p ON p.product_id = s.product_id
GROUP BY p.product_id, p.name
ORDER BY total_sold DESC
LIMIT 10;
