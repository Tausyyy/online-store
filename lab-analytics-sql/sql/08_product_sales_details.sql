WITH product_sales AS (
    SELECT
        p.product_id,
        p.name AS product_name,
        c.name AS category_name,
        SUM(oi.quantity) AS units_sold,
        COUNT(DISTINCT o.order_id) AS orders_count,
        SUM(oi.quantity * oi.fixed_price) AS total_revenue
    FROM products p
    JOIN categories c
        ON c.category_id = p.category_id
    JOIN sku s
        ON s.product_id = p.product_id
    JOIN order_items oi
        ON oi.sku_id = s.sku_id
    JOIN orders o
        ON o.order_id = oi.order_id
    GROUP BY
        p.product_id,
        p.name,
        c.name
)

SELECT
    product_id,
    product_name,
    category_name,
    units_sold,
    orders_count,
    total_revenue,
    ROUND(
        100.0 * total_revenue
        / NULLIF(SUM(total_revenue) OVER (), 0),
        2
    ) AS revenue_share_percent
FROM product_sales
ORDER BY total_revenue DESC;