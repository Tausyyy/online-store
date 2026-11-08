SELECT
    c.customer_id,
    c.email,
    SUM(oi.quantity * oi.fixed_price) AS total_spent
FROM customers c
JOIN orders o
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON oi.order_id = o.order_id
GROUP BY
    c.customer_id,
    c.email
HAVING SUM(oi.quantity * oi.fixed_price) > (
    SELECT AVG(customer_total)
    FROM (
        SELECT
            o.customer_id,
            SUM(oi.quantity * oi.fixed_price) AS customer_total
        FROM orders o
        JOIN order_items oi
            ON oi.order_id = o.order_id
        GROUP BY o.customer_id
    ) AS customer_totals
)
ORDER BY total_spent DESC;