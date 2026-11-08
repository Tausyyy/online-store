WITH customer_spending AS (
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
)

SELECT
    customer_id,
    email,
    total_spent,
    DENSE_RANK() OVER (
        ORDER BY total_spent DESC
    ) AS spending_rank
FROM customer_spending
ORDER BY spending_rank;