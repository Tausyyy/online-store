SELECT
    p.name AS product_name,
    SUM(oi.quantity) AS total_sold
FROM products p
JOIN sku s
    ON p.product_id = s.product_id
JOIN order_items oi
    ON s.sku_id = oi.sku_id
GROUP BY p.name
ORDER BY total_sold DESC
LIMIT 10;
