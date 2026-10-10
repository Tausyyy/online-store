SELECT
    p.name AS product_name,
    SUM(t.sold) AS total_sold
FROM (
    SELECT sku_id, SUM(quantity) AS sold
    FROM order_items
    GROUP BY sku_id
) AS t
JOIN sku s
    ON s.sku_id = t.sku_id
JOIN products p
    ON p.product_id = s.product_id
GROUP BY p.name
ORDER BY total_sold DESC
LIMIT 10;
