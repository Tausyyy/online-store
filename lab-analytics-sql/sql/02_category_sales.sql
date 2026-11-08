SELECT
    c.category_id,
    c.name AS category_name,
    SUM(oi.quantity) AS units_sold,
    SUM(oi.quantity * oi.fixed_price) AS total_revenue,
    ROUND(
        SUM(oi.quantity * oi.fixed_price)
        / NULLIF(SUM(oi.quantity), 0),
        2
    ) AS average_unit_price
FROM categories c
JOIN products p
    ON p.category_id = c.category_id
JOIN sku s
    ON s.product_id = p.product_id
JOIN order_items oi
    ON oi.sku_id = s.sku_id
JOIN orders o
    ON o.order_id = oi.order_id
GROUP BY
    c.category_id,
    c.name
ORDER BY total_revenue DESC;