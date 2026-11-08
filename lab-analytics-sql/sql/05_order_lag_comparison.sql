WITH order_totals AS (
    SELECT
        o.order_id,
        o.customer_id,
        c.email,
        o.created_at,
        SUM(oi.quantity * oi.fixed_price) AS order_total
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    JOIN order_items oi
        ON oi.order_id = o.order_id
    GROUP BY
        o.order_id,
        o.customer_id,
        c.email,
        o.created_at
)

SELECT
    order_id,
    customer_id,
    email,
    created_at,
    order_total,
    LAG(order_total) OVER (
        PARTITION BY customer_id
        ORDER BY created_at
    ) AS previous_order_total,
    order_total - LAG(order_total) OVER (
        PARTITION BY customer_id
        ORDER BY created_at
    ) AS difference_from_previous
FROM order_totals
ORDER BY customer_id, created_at;