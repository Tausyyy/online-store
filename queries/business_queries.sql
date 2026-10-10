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


SELECT
    p.name AS product_name,
    SUM(oi.quantity) AS total_sold
FROM products p
JOIN sku s
    ON p.product_id = s.product_id
JOIN order_items oi
    ON s.sku_id = oi.sku_id
GROUP BY p.name
ORDER BY total_sold DESC
LIMIT 10;


SELECT
    c.name AS category,
    SUM(oi.quantity * oi.fixed_price) AS revenue
FROM categories c
JOIN products p
    ON c.category_id = p.category_id
JOIN sku s
    ON p.product_id = s.product_id
JOIN order_items oi
    ON s.sku_id = oi.sku_id
GROUP BY c.name
ORDER BY revenue DESC;


SELECT
    c.customer_id,
    c.email,
    COUNT(o.order_id) AS orders_count
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.email
HAVING COUNT(o.order_id) > 5;


SELECT
    p.name AS product_name,
    s.size,
    s.color,
    s.stock_quantity
FROM products p
JOIN sku s
    ON p.product_id = s.product_id
WHERE s.stock_quantity < 10
ORDER BY s.stock_quantity;
