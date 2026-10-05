INSERT INTO categories(name, description)
VALUES ('Constraint Test Category', 'fixture')
ON CONFLICT (name) DO NOTHING;

INSERT INTO customers(email, password_hash, phone, role)
VALUES ('constraint-test@example.com', 'hash', '+70000000000', 'customer')
ON CONFLICT (email) DO NOTHING;

INSERT INTO products(category_id, name, description, brand, publication_status)
SELECT c.category_id, 'Constraint Test Product', 'fixture', 'TestBrand', 'draft'
FROM categories c
WHERE c.name = 'Constraint Test Category'
  AND NOT EXISTS (
      SELECT 1 FROM products p WHERE p.name = 'Constraint Test Product'
  );

INSERT INTO sku(product_id, article, size, color, price, stock_quantity, status)
SELECT p.product_id, 'CONSTRAINT-TEST-SKU', 'M', 'Black', 100, 10, 'draft'
FROM products p
WHERE p.name = 'Constraint Test Product'
  AND NOT EXISTS (
      SELECT 1 FROM sku s WHERE s.article = 'CONSTRAINT-TEST-SKU'
  );

INSERT INTO carts(customer_id, status, created_at, expires_at)
SELECT c.customer_id, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '7 days'
FROM customers c
WHERE c.email = 'constraint-test@example.com'
  AND NOT EXISTS (
      SELECT 1 FROM carts ca
      WHERE ca.customer_id = c.customer_id AND ca.status = 'active'
  );

INSERT INTO orders(
    customer_id, status, customer_name, customer_phone,
    delivery_method, payment_method, created_at
)
SELECT c.customer_id, 'created', 'Constraint Test User', '+70000000000',
       'pickup', 'card', CURRENT_TIMESTAMP
FROM customers c
WHERE c.email = 'constraint-test@example.com'
  AND NOT EXISTS (
      SELECT 1 FROM orders o
      WHERE o.customer_id = c.customer_id AND o.customer_name = 'Constraint Test User'
  );


CREATE OR REPLACE FUNCTION pg_temp.assert_constraint_violation(
    p_test_name text,
    p_sql text,
    p_expected_state text
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
    v_state text := NULL;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
    END;

    IF v_state IS NULL THEN
        RAISE EXCEPTION 'TEST_FAILED: % — операция неожиданно прошла', p_test_name;
    END IF;

    IF v_state <> p_expected_state THEN
        RAISE EXCEPTION 'TEST_FAILED: % — ожидался SQLSTATE %, получен %',
            p_test_name, p_expected_state, v_state;
    END IF;

    RAISE NOTICE 'PASS: % (SQLSTATE %)', p_test_name, p_expected_state;
END $$;

-- 1. NOT NULL: categories.name
SELECT pg_temp.assert_constraint_violation(
    'categories.name NOT NULL',
    $$INSERT INTO categories(name) VALUES (NULL)$$,
    '23502'
);

-- 2. UNIQUE: customers.email
SELECT pg_temp.assert_constraint_violation(
    'customers.email UNIQUE',
    $$INSERT INTO customers(email, password_hash, role)
      VALUES ('legacy@example.com', 'negative-test', 'customer')$$,
    '23505'
);

-- 3. UNIQUE: sku.article
SELECT pg_temp.assert_constraint_violation(
    'sku.article UNIQUE',
    $$INSERT INTO sku(product_id, article, size, color, price, stock_quantity, status)
      VALUES ((SELECT product_id FROM products ORDER BY product_id LIMIT 1),
               'CONSTRAINT-TEST-SKU', 'S', 'Black', 1000, 1, 'draft')$$,
    '23505'
);

-- 4. CHECK: SKU price cannot be negative.
SELECT pg_temp.assert_constraint_violation(
    'sku.price >= 0',
    $$INSERT INTO sku(product_id, article, size, color, price, stock_quantity, status)
      VALUES ((SELECT product_id FROM products ORDER BY product_id LIMIT 1),
               'NEG-PRICE', 'S', 'Black', -1, 1, 'draft')$$,
    '23514'
);

-- 5. CHECK: SKU stock cannot be negative.
SELECT pg_temp.assert_constraint_violation(
    'sku.stock_quantity >= 0',
    $$INSERT INTO sku(product_id, article, size, color, price, stock_quantity, status)
      VALUES ((SELECT product_id FROM products ORDER BY product_id LIMIT 1),
               'NEG-STOCK', 'S', 'Black', 100, -1, 'draft')$$,
    '23514'
);

-- 6. NOT NULL + CHECK: cart item quantity must be positive.
SELECT pg_temp.assert_constraint_violation(
    'cart_items.quantity > 0',
    $$INSERT INTO cart_items(cart_id, sku_id, quantity)
      VALUES ((SELECT cart_id FROM carts ORDER BY cart_id LIMIT 1),
              (SELECT sku_id FROM sku ORDER BY sku_id LIMIT 1), 0)$$,
    '23514'
);

-- 7. CHECK: order item quantity must be positive.
SELECT pg_temp.assert_constraint_violation(
    'order_items.quantity > 0',
    $$INSERT INTO order_items(order_id, sku_id, quantity, fixed_price)
      VALUES ((SELECT order_id FROM orders ORDER BY order_id LIMIT 1),
              (SELECT sku_id FROM sku ORDER BY sku_id LIMIT 1), 0, 100)$$,
    '23514'
);

-- 8. CHECK: fixed order-item price cannot be negative.
SELECT pg_temp.assert_constraint_violation(
    'order_items.fixed_price >= 0',
    $$INSERT INTO order_items(order_id, sku_id, quantity, fixed_price)
      VALUES ((SELECT order_id FROM orders ORDER BY order_id LIMIT 1),
              (SELECT sku_id FROM sku ORDER BY sku_id LIMIT 1), 1, -0.01)$$,
    '23514'
);

-- 9. FOREIGN KEY: product must reference an existing category.
SELECT pg_temp.assert_constraint_violation(
    'products.category_id FOREIGN KEY',
    $$INSERT INTO products(category_id, name, brand, publication_status)
      VALUES (-999999, 'FK negative test', 'TestBrand', 'draft')$$,
    '23503'
);

-- 10. FOREIGN KEY: SKU must reference an existing product.
SELECT pg_temp.assert_constraint_violation(
    'sku.product_id FOREIGN KEY',
    $$INSERT INTO sku(product_id, article, size, color, price, stock_quantity, status)
      VALUES (-999999, 'FK-SKU-TEST', 'S', 'Black', 100, 1, 'draft')$$,
    '23503'
);

DROP FUNCTION pg_temp.assert_constraint_violation(text, text, text);
