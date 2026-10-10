SELECT
    c.customer_id,
    c.email,
    o.order_id,
    o.created_at,
    p.name AS product_name,
    s.size,
    s.color,
    oi.quantity,
    oi.fixed_price
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
JOIN sku s
    ON oi.sku_id = s.sku_id
JOIN products p
    ON s.product_id = p.product_id
WHERE c.customer_id = 15;
