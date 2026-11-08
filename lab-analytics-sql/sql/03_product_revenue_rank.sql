SELECT
    p.product_id,
    p.name AS product_name,
    SUM(oi.quantity) AS units_sold,
    SUM(oi.quantity * oi.fixed_price) AS total_revenue,
    RANK() OVER (
        ORDER BY SUM(oi.quantity * oi.fixed_price) DESC
    ) AS revenue_rank
FROM products p
JOIN sku s
    ON s.product_id = p.product_id
JOIN order_items oi
    ON oi.sku_id = s.sku_id
JOIN orders o
    ON o.order_id = oi.order_id
GROUP BY
    p.product_id,
    p.name
ORDER BY revenue_rank;