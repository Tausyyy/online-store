WITH daily_revenue AS (
    SELECT
        DATE(o.created_at) AS order_date,
        SUM(oi.quantity * oi.fixed_price) AS daily_revenue
    FROM orders o
    JOIN order_items oi
        ON oi.order_id = o.order_id
    GROUP BY DATE(o.created_at)
)

SELECT
    order_date,
    daily_revenue,
    SUM(daily_revenue) OVER (
        ORDER BY order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue
FROM daily_revenue
ORDER BY order_date;