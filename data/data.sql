INSERT INTO categories (name, description)
VALUES
    ('Футболки', 'Повседневные футболки'),
    ('Худи', 'Толстовки с капюшоном'),
    ('Джинсы', 'Мужские и женские джинсы');

INSERT INTO customers (
    email,
    password_hash,
    phone,
    role
)
VALUES
    ('ivan@example.com', 'hash_ivan', '+79990000001', 'customer'),
    ('anna@example.com', 'hash_anna', '+79990000002', 'customer');

INSERT INTO products (
    category_id,
    name,
    description,
    brand,
    publication_status
)
VALUES
(
    (
        SELECT category_id
        FROM categories
        WHERE name = 'Футболки'
    ),
    'Basic T-Shirt',
    'Базовая хлопковая футболка',
    'BasicBrand',
    'published'
),
(
    (
        SELECT category_id
        FROM categories
        WHERE name = 'Худи'
    ),
    'Classic Hoodie',
    'Классическое худи с капюшоном',
    'StreetBrand',
    'published'
),
(
    (
        SELECT category_id
        FROM categories
        WHERE name = 'Джинсы'
    ),
    'Classic Jeans',
    'Классические прямые джинсы',
    'DenimBrand',
    'published'
);


INSERT INTO sku (
    product_id,
    article,
    size,
    color,
    price,
    stock_quantity,
    status
)
VALUES
(
    (
        SELECT product_id
        FROM products
        WHERE name = 'Basic T-Shirt'
    ),
    'TSH-BLK-M',
    'M',
    'Black',
    1999.00,
    20,
    'on_sale'
),
(
    (
        SELECT product_id
        FROM products
        WHERE name = 'Basic T-Shirt'
    ),
    'TSH-WHT-L',
    'L',
    'White',
    1999.00,
    15,
    'on_sale'
),
(
    (
        SELECT product_id
        FROM products
        WHERE name = 'Classic Hoodie'
    ),
    'HOD-GRY-M',
    'M',
    'Gray',
    3999.00,
    10,
    'on_sale'
),
(
    (
        SELECT product_id
        FROM products
        WHERE name = 'Classic Jeans'
    ),
    'JNS-BLU-32',
    '32',
    'Blue',
    4999.00,
    5,
    'draft'
);

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
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP + INTERVAL '7 days'
);


INSERT INTO cart_items (
    cart_id,
    sku_id,
    quantity
)
VALUES
(
    (
        SELECT c.cart_id
        FROM carts c
        JOIN customers cu
            ON cu.customer_id = c.customer_id
        WHERE cu.email = 'ivan@example.com'
          AND c.status = 'active'
        ORDER BY c.cart_id DESC
        LIMIT 1
    ),
    (
        SELECT sku_id
        FROM sku
        WHERE article = 'TSH-BLK-M'
    ),
    2
),
(
    (
        SELECT c.cart_id
        FROM carts c
        JOIN customers cu
            ON cu.customer_id = c.customer_id
        WHERE cu.email = 'ivan@example.com'
          AND c.status = 'active'
        ORDER BY c.cart_id DESC
        LIMIT 1
    ),
    (
        SELECT sku_id
        FROM sku
        WHERE article = 'HOD-GRY-M'
    ),
    1
);

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
        ORDER BY o.order_id DESC
        LIMIT 1
    ),
    (
        SELECT sku_id
        FROM sku
        WHERE article = 'TSH-WHT-L'
    ),
    1,
    (
        SELECT price
        FROM sku
        WHERE article = 'TSH-WHT-L'
    )
);