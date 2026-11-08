SELECT
    c.customer_id,
    c.email,
    COUNT(DISTINCT o.order_id) AS orders_count,
    COALESCE(SUM(oi.quantity * oi.fixed_price), 0) AS total_spent
FROM customers c
LEFT JOIN orders o
    ON o.customer_id = c.customer_id
LEFT JOIN order_items oi
    ON oi.order_id = o.order_id
GROUP BY
    c.customer_id,
    c.email
ORDER BY total_spent DESC;