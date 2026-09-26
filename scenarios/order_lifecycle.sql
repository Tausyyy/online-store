-- ============================================
-- ORDER LIFECYCLE
--
-- Created
-- -> Awaiting Payment
-- -> Paid
-- -> In Assembly
-- -> Handed to Delivery
-- -> Delivered
-- -> Return Processed
-- ============================================


-- ============================================
-- 1. CREATE ORDER
-- ============================================

INSERT INTO orders (
    customer_id,
    status,
    customer_name,
    customer_phone,
    delivery_method,
    payment_method,
    created_at
)
VALUES
(
    (
        SELECT customer_id
        FROM customers
        WHERE email = 'anna@example.com'
    ),
    'created',
    'Анна Иванова',
    '+79990000002',
    'pickup',
    'card',
    CURRENT_TIMESTAMP
);


-- ============================================
-- 2. ADD ORDER ITEM
-- ============================================

INSERT INTO order_items (
    order_id,
    sku_id,
    quantity,
    fixed_price
)
VALUES
(
    (
        SELECT o.order_id
        FROM orders o
        JOIN customers c
            ON c.customer_id = o.customer_id
        WHERE c.email = 'anna@example.com'
          AND o.status = 'created'
        ORDER BY o.order_id DESC
        LIMIT 1
    ),
    (
        SELECT sku_id
        FROM sku
        WHERE article = 'TSH-WHT-L'
    ),
    2,
    (
        SELECT price
        FROM sku
        WHERE article = 'TSH-WHT-L'
    )
);


-- ============================================
-- 3. CHECK ORDER BEFORE STOCK DECREASE
-- ============================================

SELECT
    o.order_id,
    o.status,
    c.email,
    oi.quantity,
    oi.fixed_price,
    s.article,
    s.stock_quantity
FROM orders o
JOIN customers c
    ON c.customer_id = o.customer_id
JOIN order_items oi
    ON oi.order_id = o.order_id
JOIN sku s
    ON s.sku_id = oi.sku_id
WHERE o.order_id = (
    SELECT o2.order_id
    FROM orders o2
    JOIN customers c2
        ON c2.customer_id = o2.customer_id
    WHERE c2.email = 'anna@example.com'
      AND o2.status = 'created'
    ORDER BY o2.order_id DESC
    LIMIT 1
);


-- ============================================
-- 4. CHECK STOCK AVAILABILITY
-- ============================================

DO $$
DECLARE
    required_quantity INTEGER;
    available_quantity INTEGER;
BEGIN
    SELECT
        oi.quantity,
        s.stock_quantity
    INTO
        required_quantity,
        available_quantity
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    JOIN order_items oi
        ON oi.order_id = o.order_id
    JOIN sku s
        ON s.sku_id = oi.sku_id
    WHERE o.order_id = (
        SELECT o2.order_id
        FROM orders o2
        JOIN customers c2
            ON c2.customer_id = o2.customer_id
        WHERE c2.email = 'anna@example.com'
          AND o2.status = 'created'
        ORDER BY o2.order_id DESC
        LIMIT 1
    );

    IF required_quantity IS NULL THEN
        RAISE EXCEPTION 'Не удалось определить количество товара для заказа';
    END IF;

    IF available_quantity < required_quantity THEN
        RAISE EXCEPTION
            'Недостаточно товара: требуется %, доступно %',
            required_quantity,
            available_quantity;
    END IF;
END $$;


-- ============================================
-- 5. DECREASE STOCK
-- ============================================

UPDATE sku s
SET stock_quantity = s.stock_quantity - oi.quantity
FROM order_items oi
WHERE oi.sku_id = s.sku_id
  AND oi.order_id = (
      SELECT o.order_id
      FROM orders o
      JOIN customers c
          ON c.customer_id = o.customer_id
      WHERE c.email = 'anna@example.com'
        AND o.status = 'created'
      ORDER BY o.order_id DESC
      LIMIT 1
  );


-- Проверяем остаток
SELECT
    article,
    stock_quantity
FROM sku
WHERE article = 'TSH-WHT-L';


-- ============================================
-- 6. CREATED -> AWAITING PAYMENT
-- ============================================

UPDATE orders
SET status = 'awaiting_payment'
WHERE order_id = (
    SELECT o.order_id
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE c.email = 'anna@example.com'
    ORDER BY o.order_id DESC
    LIMIT 1
)
AND status = 'created';


-- ============================================
-- 7. AWAITING PAYMENT -> PAID
-- ============================================

UPDATE orders
SET status = 'paid'
WHERE order_id = (
    SELECT o.order_id
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE c.email = 'anna@example.com'
    ORDER BY o.order_id DESC
    LIMIT 1
)
AND status = 'awaiting_payment';


-- ============================================
-- 8. PAID -> IN ASSEMBLY
-- ============================================

UPDATE orders
SET status = 'in_assembly'
WHERE order_id = (
    SELECT o.order_id
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE c.email = 'anna@example.com'
    ORDER BY o.order_id DESC
    LIMIT 1
)
AND status = 'paid';


-- ============================================
-- 9. IN ASSEMBLY -> HANDED TO DELIVERY
-- ============================================

UPDATE orders
SET status = 'handed_to_delivery'
WHERE order_id = (
    SELECT o.order_id
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE c.email = 'anna@example.com'
    ORDER BY o.order_id DESC
    LIMIT 1
)
AND status = 'in_assembly';


-- ============================================
-- 10. HANDED TO DELIVERY -> DELIVERED
-- ============================================

UPDATE orders
SET status = 'delivered'
WHERE order_id = (
    SELECT o.order_id
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE c.email = 'anna@example.com'
    ORDER BY o.order_id DESC
    LIMIT 1
)
AND status = 'handed_to_delivery';


-- ============================================
-- 11. DELIVERED -> RETURN PROCESSED
-- ============================================

UPDATE orders
SET status = 'return_processed'
WHERE order_id = (
    SELECT o.order_id
    FROM orders o
    JOIN customers c
        ON c.customer_id = o.customer_id
    WHERE c.email = 'anna@example.com'
    ORDER BY o.order_id DESC
    LIMIT 1
)
AND status = 'delivered';


-- ============================================
-- FINAL RESULT
-- ============================================

SELECT
    o.order_id,
    o.status,
    c.email,
    o.customer_name,
    o.customer_phone,
    o.delivery_method,
    o.payment_method,
    oi.quantity,
    oi.fixed_price,
    s.article,
    s.stock_quantity
FROM orders o
JOIN customers c
    ON c.customer_id = o.customer_id
JOIN order_items oi
    ON oi.order_id = o.order_id
JOIN sku s
    ON s.sku_id = oi.sku_id
WHERE o.order_id = (
    SELECT o2.order_id
    FROM orders o2
    JOIN customers c2
        ON c2.customer_id = o2.customer_id
    WHERE c2.email = 'anna@example.com'
    ORDER BY o2.order_id DESC
    LIMIT 1
);