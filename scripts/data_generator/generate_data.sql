\set ON_ERROR_STOP on

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

SELECT set_config('app.gen_tag', :'tag', true);
SELECT set_config('app.gen_seed', :'seed', true);
SELECT set_config('app.gen_items', :'order_items_count', true);

DO $$
DECLARE
    v_tag   TEXT   := current_setting('app.gen_tag');
    v_seed  BIGINT := current_setting('app.gen_seed')::BIGINT;
    v_items BIGINT := current_setting('app.gen_items')::BIGINT;
BEGIN
    IF v_tag !~ '^[a-zA-Z0-9]{1,12}$' THEN
        RAISE EXCEPTION
            'tag должен содержать от 1 до 12 латинских букв или цифр';
    END IF;

    IF v_seed < 0 OR v_seed > 1000000000 THEN
        RAISE EXCEPTION 'seed должен находиться в диапазоне 0..1000000000';
    END IF;

    IF NOT (
        v_items BETWEEN 50000 AND 100000
        OR v_items >= 3000000
    ) THEN
        RAISE EXCEPTION
            'Укажите 50000..100000 строк для разработки или минимум 3000000 для нагрузки';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM categories
        WHERE left(name, length('g' || v_tag || '_cat_'))
            = 'g' || v_tag || '_cat_'
    ) THEN
        RAISE EXCEPTION 'Набор с tag=% уже существует в categories', v_tag;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM customers
        WHERE left(email, length('g' || v_tag || '_'))
            = 'g' || v_tag || '_'
    ) THEN
        RAISE EXCEPTION 'Набор с tag=% уже существует в customers', v_tag;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM products
        WHERE left(name, length('g' || v_tag || '_product_'))
            = 'g' || v_tag || '_product_'
    ) THEN
        RAISE EXCEPTION 'Набор с tag=% уже существует в products', v_tag;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM sku
        WHERE left(article, length('g' || v_tag || '_sku_'))
            = 'g' || v_tag || '_sku_'
    ) THEN
        RAISE EXCEPTION 'Набор с tag=% уже существует в sku', v_tag;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM orders
        WHERE left(customer_name, length('g' || v_tag || '_order_'))
            = 'g' || v_tag || '_order_'
    ) THEN
        RAISE EXCEPTION 'Набор с tag=% уже существует в orders', v_tag;
    END IF;
END;
$$;


SELECT setseed(
    current_setting('app.gen_seed')::BIGINT / 500000000.0 - 1.0
);

CREATE TEMP TABLE gen_params ON COMMIT DROP AS
SELECT
    current_setting('app.gen_items')::BIGINT AS item_count,

    GREATEST(
        1000,
        CEIL(current_setting('app.gen_items')::NUMERIC / 100)::INTEGER
    ) AS customer_count,

    GREATEST(
        500,
        CEIL(current_setting('app.gen_items')::NUMERIC / 1000)::INTEGER
    ) AS product_count,

    GREATEST(
        10000,
        CEIL(current_setting('app.gen_items')::NUMERIC / 10)::INTEGER
    ) AS order_count,

    20::INTEGER AS category_count,
    5::INTEGER AS sku_per_product,

    TIMESTAMP '2026-10-10 12:00:00' AS base_timestamp;


CREATE TEMP TABLE gen_categories_src ON COMMIT DROP AS
SELECT
    n,
    'g' || current_setting('app.gen_tag') || '_cat_' || n AS name,
    'Generated test category ' || n AS description
FROM generate_series(1, 20) AS gs(n);


CREATE TEMP TABLE gen_customers_src ON COMMIT DROP AS
SELECT
    gs.n,

    'g' || current_setting('app.gen_tag')
        || '_customer_' || gs.n || '@example.test' AS email,

    'test_generated_hash_' || gs.n AS password_hash,

    '+7900' || LPAD(gs.n::TEXT, 7, '0') AS phone,

    CASE
        WHEN gs.n % 100 = 0 THEN 'admin'
        ELSE 'customer'
    END AS role
FROM generate_series(
    1,
    (SELECT customer_count FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_products_src ON COMMIT DROP AS
SELECT
    gs.n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT category_count FROM gen_params)
    )::INTEGER AS category_n,

    'g' || current_setting('app.gen_tag')
        || '_product_' || gs.n AS name,

    'Generated product description ' || gs.n AS description,

    CASE gs.n % 6
        WHEN 0 THEN 'Brand A'
        WHEN 1 THEN 'Brand B'
        WHEN 2 THEN 'Brand C'
        WHEN 3 THEN 'Brand D'
        WHEN 4 THEN 'Brand E'
        ELSE 'Generic Brand'
    END AS brand,

    CASE
        WHEN (gs.n - 1) % 10 < 7 THEN 'published'
        WHEN (gs.n - 1) % 10 < 9 THEN 'draft'
        ELSE 'archived'
    END AS publication_status

FROM generate_series(
    1,
    (SELECT product_count FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_sku_src ON COMMIT DROP AS
SELECT
    p.n * 5 - 5 + v.variant_n AS n,
    p.n AS product_n,

    'g' || current_setting('app.gen_tag')
        || '_sku_' || p.n || '_' || v.variant_n AS article,

    CASE v.variant_n
        WHEN 1 THEN 'S'
        WHEN 2 THEN 'M'
        WHEN 3 THEN 'L'
        WHEN 4 THEN 'XL'
        ELSE 'XS'
    END AS size,

    CASE v.variant_n % 4
        WHEN 0 THEN 'black'
        WHEN 1 THEN 'white'
        WHEN 2 THEN 'blue'
        ELSE 'red'
    END AS color,

    (
        500 + FLOOR(POWER(random(), 2) * 19500)
    )::NUMERIC(10, 2) AS price,

    CASE
        WHEN p.publication_status <> 'published' THEN 0
        WHEN v.variant_n IN (1, 2) THEN
            3000 + FLOOR(random() * 5001)::INTEGER
        WHEN v.variant_n = 3 AND p.n % 5 <> 0 THEN
            3000 + FLOOR(random() * 5001)::INTEGER
        ELSE 0
    END AS stock_quantity,

    CASE
        WHEN p.publication_status = 'archived' THEN 'archived'
        WHEN p.publication_status = 'draft' THEN
            CASE
                WHEN v.variant_n < 5 THEN 'draft'
                ELSE 'archived'
            END
        WHEN v.variant_n IN (1, 2) THEN 'on_sale'
        WHEN v.variant_n = 3 AND p.n % 5 <> 0 THEN 'on_sale'
        WHEN v.variant_n IN (3, 4) THEN 'out_of_stock'
        ELSE 'archived'
    END AS status

FROM gen_products_src p
CROSS JOIN generate_series(1, 5) AS v(variant_n);


CREATE TEMP TABLE gen_carts_src ON COMMIT DROP AS
SELECT
    gs.n,

    CEIL(gs.n::NUMERIC / 2)::INTEGER AS customer_n,

    CASE
        WHEN (gs.n - 1) % 10 < 4 THEN 'active'
        WHEN (gs.n - 1) % 10 < 7 THEN 'completed'
        ELSE 'expired'
    END AS status,

    (
        (SELECT base_timestamp FROM gen_params)
        - CASE
            WHEN (gs.n - 1) % 10 < 4 THEN
                FLOOR(random() * 6)::INTEGER * INTERVAL '1 day'
            WHEN (gs.n - 1) % 10 < 7 THEN
                (8 + FLOOR(random() * 358)::INTEGER) * INTERVAL '1 day'
            ELSE
                (8 + FLOOR(random() * 180)::INTEGER) * INTERVAL '1 day'
          END
        - gs.n * INTERVAL '1 microsecond'
    ) AS created_at

FROM generate_series(
    1,
    (SELECT customer_count * 2 FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_orders_src ON COMMIT DROP AS
SELECT
    gs.n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT customer_count FROM gen_params)
    )::INTEGER AS customer_n,

    CASE
        WHEN (gs.n - 1) % 100 < 10 THEN 'created'
        WHEN (gs.n - 1) % 100 < 18 THEN 'awaiting_payment'
        WHEN (gs.n - 1) % 100 < 30 THEN 'paid'
        WHEN (gs.n - 1) % 100 < 38 THEN 'in_assembly'
        WHEN (gs.n - 1) % 100 < 45 THEN 'handed_to_delivery'
        WHEN (gs.n - 1) % 100 < 90 THEN 'delivered'
        WHEN (gs.n - 1) % 100 < 95 THEN 'return_processed'
        ELSE 'cancelled'
    END AS status,

    'g' || current_setting('app.gen_tag') || '_order_' || gs.n
        AS customer_name,

    '+7911' || LPAD(gs.n::TEXT, 7, '0') AS customer_phone,

    CASE gs.n % 3
        WHEN 0 THEN 'courier'
        WHEN 1 THEN 'pickup'
        ELSE 'post'
    END AS delivery_method,

    CASE gs.n % 3
        WHEN 0 THEN 'card'
        WHEN 1 THEN 'cash'
        ELSE 'online'
    END AS payment_method,

    (
        (SELECT base_timestamp FROM gen_params)
        - CASE
            WHEN (gs.n - 1) % 100 < 10 THEN
                INTERVAL '0 days'
            WHEN (gs.n - 1) % 100 < 18 THEN
                FLOOR(random() * 2)::INTEGER * INTERVAL '1 day'
            WHEN (gs.n - 1) % 100 < 38 THEN
                (1 + FLOOR(random() * 3)::INTEGER) * INTERVAL '1 day'
            WHEN (gs.n - 1) % 100 < 45 THEN
                (2 + FLOOR(random() * 6)::INTEGER) * INTERVAL '1 day'
            WHEN (gs.n - 1) % 100 < 95 THEN
                (8 + FLOOR(random() * 1088)::INTEGER) * INTERVAL '1 day'
            ELSE
                FLOOR(random() * 8)::INTEGER * INTERVAL '1 day'
          END
        - gs.n * INTERVAL '1 microsecond'
    ) AS created_at

FROM generate_series(
    1,
    (SELECT order_count FROM gen_params)
) AS gs(n);


INSERT INTO categories (name, description)
SELECT name, description
FROM gen_categories_src
ORDER BY n;


CREATE TEMP TABLE gen_categories_map ON COMMIT DROP AS
SELECT s.n, c.category_id
FROM gen_categories_src s
JOIN categories c ON c.name = s.name;


INSERT INTO customers (email, password_hash, phone, role)
SELECT email, password_hash, phone, role
FROM gen_customers_src
ORDER BY n;


CREATE TEMP TABLE gen_customers_map ON COMMIT DROP AS
SELECT s.n, c.customer_id
FROM gen_customers_src s
JOIN customers c ON c.email = s.email;


INSERT INTO products (
    category_id,
    name,
    description,
    brand,
    publication_status
)
SELECT
    cm.category_id,
    p.name,
    p.description,
    p.brand,
    p.publication_status
FROM gen_products_src p
JOIN gen_categories_map cm ON cm.n = p.category_n
ORDER BY p.n;


CREATE TEMP TABLE gen_products_map ON COMMIT DROP AS
SELECT s.n, p.product_id
FROM gen_products_src s
JOIN products p ON p.name = s.name;


INSERT INTO sku (
    product_id,
    article,
    size,
    color,
    price,
    stock_quantity,
    status
)
SELECT
    pm.product_id,
    s.article,
    s.size,
    s.color,
    s.price,
    s.stock_quantity,
    s.status
FROM gen_sku_src s
JOIN gen_products_map pm ON pm.n = s.product_n
ORDER BY s.n;


CREATE TEMP TABLE gen_sku_map ON COMMIT DROP AS
SELECT
    src.n,
    k.sku_id,
    src.price,
    src.stock_quantity AS initial_stock,
    src.status AS initial_status
FROM gen_sku_src src
JOIN sku k ON k.article = src.article;


CREATE TEMP TABLE gen_sellable_sku_map ON COMMIT DROP AS
SELECT
    ROW_NUMBER() OVER (ORDER BY n)::INTEGER AS sellable_n,
    n,
    sku_id,
    price,
    initial_stock
FROM gen_sku_map
WHERE initial_status = 'on_sale'
  AND initial_stock > 0;


DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM gen_sellable_sku_map) THEN
        RAISE EXCEPTION 'Не создано ни одного SKU со статусом on_sale';
    END IF;
END;
$$;


INSERT INTO carts (
    customer_id,
    status,
    created_at,
    expires_at
)
SELECT
    cm.customer_id,
    c.status,
    c.created_at,
    c.created_at + INTERVAL '7 days'
FROM gen_carts_src c
JOIN gen_customers_map cm ON cm.n = c.customer_n
ORDER BY c.n;


CREATE TEMP TABLE gen_carts_map ON COMMIT DROP AS
SELECT
    src.n,
    c.cart_id
FROM gen_carts_src src
JOIN gen_customers_map cm ON cm.n = src.customer_n
JOIN carts c
    ON c.customer_id = cm.customer_id
   AND c.status = src.status
   AND c.created_at = src.created_at
   AND c.expires_at = src.created_at + INTERVAL '7 days';


INSERT INTO orders (
    customer_id,
    status,
    customer_name,
    customer_phone,
    delivery_method,
    payment_method,
    created_at
)
SELECT
    cm.customer_id,
    o.status,
    o.customer_name,
    o.customer_phone,
    o.delivery_method,
    o.payment_method,
    o.created_at
FROM gen_orders_src o
JOIN gen_customers_map cm ON cm.n = o.customer_n
ORDER BY o.n;


CREATE TEMP TABLE gen_orders_map ON COMMIT DROP AS
SELECT src.n, o.order_id
FROM gen_orders_src src
JOIN orders o ON o.customer_name = src.customer_name;


CREATE TEMP TABLE gen_order_items_src ON COMMIT DROP AS
SELECT
    gs.n,

    (
        FLOOR(
            (gs.n - 1)::NUMERIC
            * (SELECT order_count FROM gen_params)
            / (SELECT item_count FROM gen_params)
        ) + 1
    )::INTEGER AS order_n,

    (
        ((gs.n - 1) % (SELECT COUNT(*) FROM gen_sellable_sku_map)) + 1
    )::INTEGER AS sellable_n,

    1 + FLOOR(random() * 3)::INTEGER AS quantity

FROM generate_series(
    1,
    (SELECT item_count FROM gen_params)
) AS gs(n);


DO $$
DECLARE
    v_bad_stock BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO v_bad_stock
    FROM (
        SELECT
            src.sellable_n,
            SUM(src.quantity) AS required_quantity,
            sm.initial_stock
        FROM gen_order_items_src src
        JOIN gen_orders_src o ON o.n = src.order_n
        JOIN gen_sellable_sku_map sm
            ON sm.sellable_n = src.sellable_n
        WHERE o.status <> 'cancelled'
        GROUP BY src.sellable_n, sm.initial_stock
        HAVING SUM(src.quantity) > sm.initial_stock
    ) q;

    IF v_bad_stock > 0 THEN
        RAISE EXCEPTION
            'Недостаточно начального остатка для % SKU',
            v_bad_stock;
    END IF;
END;
$$;


INSERT INTO order_items (
    order_id,
    sku_id,
    quantity,
    fixed_price
)
SELECT
    om.order_id,
    sm.sku_id,
    src.quantity,
    sm.price
FROM gen_order_items_src src
JOIN gen_orders_map om ON om.n = src.order_n
JOIN gen_sellable_sku_map sm ON sm.sellable_n = src.sellable_n
ORDER BY src.n;


UPDATE sku s
SET
    stock_quantity = s.stock_quantity - q.required_quantity,

    status = CASE
        WHEN s.stock_quantity - q.required_quantity = 0
            THEN 'out_of_stock'
        ELSE s.status
    END

FROM (
    SELECT
        oi.sku_id,
        SUM(oi.quantity)::INTEGER AS required_quantity
    FROM order_items oi
    JOIN gen_orders_map om ON om.order_id = oi.order_id
    JOIN orders o ON o.order_id = om.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY oi.sku_id
) q

WHERE s.sku_id = q.sku_id;


CREATE TEMP TABLE gen_available_sku_map ON COMMIT DROP AS
SELECT
    ROW_NUMBER() OVER (ORDER BY sm.n)::INTEGER AS available_n,
    sm.n,
    s.sku_id,
    s.stock_quantity
FROM gen_sku_map sm
JOIN sku s ON s.sku_id = sm.sku_id
WHERE s.status = 'on_sale'
  AND s.stock_quantity > 0;


CREATE TEMP TABLE gen_cart_counts ON COMMIT DROP AS
SELECT
    c.n AS cart_n,
    1 + FLOOR(random() * 3)::INTEGER AS item_count
FROM gen_carts_src c
WHERE c.status = 'active';


CREATE TEMP TABLE gen_cart_items_src ON COMMIT DROP AS
SELECT
    c.cart_n,
    slot.n AS slot_n,

    (
        (
            ((c.cart_n::BIGINT - 1) * 3 + slot.n - 1)
            % (SELECT COUNT(*) FROM gen_available_sku_map)
        ) + 1
    )::INTEGER AS available_n,

    1 + FLOOR(random() * 3)::INTEGER AS quantity

FROM gen_cart_counts c
CROSS JOIN LATERAL generate_series(1, c.item_count) AS slot(n);


INSERT INTO cart_items (cart_id, sku_id, quantity)
SELECT
    cm.cart_id,
    sm.sku_id,
    src.quantity
FROM gen_cart_items_src src
JOIN gen_carts_map cm ON cm.n = src.cart_n
JOIN gen_available_sku_map sm ON sm.available_n = src.available_n;


DO $$
DECLARE
    v_expected BIGINT := current_setting('app.gen_items')::BIGINT;
    v_actual BIGINT;
    v_bad BIGINT;
    v_base TIMESTAMP := (
        SELECT base_timestamp FROM gen_params
    );
BEGIN
    SELECT COUNT(*)
    INTO v_actual
    FROM order_items oi
    JOIN gen_orders_map om ON om.order_id = oi.order_id;

    IF v_actual <> v_expected THEN
        RAISE EXCEPTION
            'Ожидалось % позиций заказов, создано %',
            v_expected, v_actual;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_orders_map om
    LEFT JOIN order_items oi ON oi.order_id = om.order_id
    WHERE oi.order_item_id IS NULL;

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдено заказов без позиций: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM order_items oi
    JOIN gen_orders_map om ON om.order_id = oi.order_id
    JOIN gen_sellable_sku_map sm ON sm.sku_id = oi.sku_id
    WHERE oi.fixed_price <> sm.price;

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдено позиций с некорректной фиксированной ценой: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_sku_map gm
    JOIN sku s ON s.sku_id = gm.sku_id
    WHERE s.stock_quantity < 0
       OR (s.status = 'on_sale' AND s.stock_quantity <= 0)
       OR (s.status = 'out_of_stock' AND s.stock_quantity <> 0)
       OR (s.status IN ('draft', 'archived') AND s.stock_quantity <> 0);

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдены SKU с некорректными статусами или остатками: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_products_map pm
    JOIN products p ON p.product_id = pm.product_id
    WHERE p.publication_status = 'published'
      AND NOT EXISTS (
          SELECT 1
          FROM sku s
          WHERE s.product_id = p.product_id
            AND s.status = 'on_sale'
            AND s.stock_quantity > 0
      );

    IF v_bad > 0 THEN
        RAISE EXCEPTION
            'Найдено опубликованных товаров без доступного SKU: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_carts_map cm
    JOIN carts c ON c.cart_id = cm.cart_id
    WHERE c.expires_at <> c.created_at + INTERVAL '7 days'
       OR (c.status = 'active' AND c.expires_at <= v_base)
       OR (c.status = 'expired' AND c.expires_at >= v_base);

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдены корзины с некорректными датами: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_carts_map cm
    JOIN carts c ON c.cart_id = cm.cart_id
    JOIN cart_items ci ON ci.cart_id = c.cart_id
    WHERE c.status IN ('completed', 'expired');

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдены позиции в завершённых или истёкших корзинах: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_carts_map cm
    JOIN carts c ON c.cart_id = cm.cart_id
    WHERE c.status = 'active'
      AND NOT EXISTS (
          SELECT 1
          FROM cart_items ci
          WHERE ci.cart_id = c.cart_id
      );

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдены пустые активные корзины: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM (
        SELECT
            ci.cart_id,
            ci.sku_id,
            SUM(ci.quantity) AS cart_quantity,
            s.stock_quantity
        FROM cart_items ci
        JOIN gen_carts_map cm ON cm.cart_id = ci.cart_id
        JOIN sku s ON s.sku_id = ci.sku_id
        GROUP BY ci.cart_id, ci.sku_id, s.stock_quantity
        HAVING SUM(ci.quantity) > s.stock_quantity
    ) q;

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдены позиции корзин сверх доступного остатка: %', v_bad;
    END IF;


    SELECT COUNT(*)
    INTO v_bad
    FROM gen_orders_map om
    JOIN orders o ON o.order_id = om.order_id
    WHERE o.customer_name IS NULL
       OR o.customer_phone IS NULL
       OR o.delivery_method IS NULL
       OR o.payment_method IS NULL
       OR o.created_at IS NULL
       OR o.status NOT IN (
           'created',
           'awaiting_payment',
           'paid',
           'in_assembly',
           'handed_to_delivery',
           'delivered',
           'return_processed',
           'cancelled'
       );

    IF v_bad > 0 THEN
        RAISE EXCEPTION 'Найдены заказы с некорректными полями или статусами: %', v_bad;
    END IF;


    RAISE NOTICE
        'Генерация завершена: tag=%, seed=%, order_items=%',
        current_setting('app.gen_tag'),
        current_setting('app.gen_seed'),
        v_expected;
END;
$$;

COMMIT;