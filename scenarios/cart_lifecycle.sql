-- ============================================
-- CART LIFECYCLE
--
-- Active -> Completed
-- Active -> Expired
-- ============================================


-- ============================================
-- 1. CHECK INITIAL ACTIVE CART
-- ============================================

SELECT
    c.cart_id,
    c.status,
    c.created_at,
    c.expires_at,
    cu.email,
    s.article,
    ci.quantity
FROM carts c
JOIN customers cu
    ON cu.customer_id = c.customer_id
JOIN cart_items ci
    ON ci.cart_id = c.cart_id
JOIN sku s
    ON s.sku_id = ci.sku_id
WHERE cu.email = 'ivan@example.com'
  AND c.status = 'active'
ORDER BY c.cart_id DESC
LIMIT 1;


-- ============================================
-- 2. ACTIVE -> COMPLETED
-- ============================================

UPDATE carts
SET status = 'completed'
WHERE cart_id = (
    SELECT c.cart_id
    FROM carts c
    JOIN customers cu
        ON cu.customer_id = c.customer_id
    WHERE cu.email = 'ivan@example.com'
      AND c.status = 'active'
    ORDER BY c.cart_id DESC
    LIMIT 1
)
AND status = 'active';


-- Проверяем результат
SELECT
    c.cart_id,
    c.customer_id,
    c.status,
    c.created_at,
    c.expires_at
FROM carts c
JOIN customers cu
    ON cu.customer_id = c.customer_id
WHERE cu.email = 'ivan@example.com'
ORDER BY c.cart_id DESC
LIMIT 1;


-- ============================================
-- 3. CREATE EXPIRED CART
-- ============================================

INSERT INTO carts (
    customer_id,
    status,
    created_at,
    expires_at
)
VALUES
(
    (
        SELECT customer_id
        FROM customers
        WHERE email = 'ivan@example.com'
    ),
    'active',
    CURRENT_TIMESTAMP - INTERVAL '8 days',
    CURRENT_TIMESTAMP - INTERVAL '1 day'
);


-- ============================================
-- 4. ACTIVE -> EXPIRED
-- ============================================

UPDATE carts
SET status = 'expired'
WHERE cart_id = (
    SELECT c.cart_id
    FROM carts c
    JOIN customers cu
        ON cu.customer_id = c.customer_id
    WHERE cu.email = 'ivan@example.com'
      AND c.status = 'active'
      AND c.expires_at < CURRENT_TIMESTAMP
    ORDER BY c.cart_id DESC
    LIMIT 1
)
AND status = 'active';


-- Проверяем результат
SELECT
    c.cart_id,
    c.customer_id,
    c.status,
    c.created_at,
    c.expires_at
FROM carts c
JOIN customers cu
    ON cu.customer_id = c.customer_id
WHERE cu.email = 'ivan@example.com'
ORDER BY c.cart_id;