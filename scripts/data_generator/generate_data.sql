\set ON_ERROR_STOP on


BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

SELECT set_config('app.gen_tag', :'tag', true);
SELECT set_config('app.gen_seed', :'seed', true);
SELECT set_config(
    'app.gen_items',
    :'order_items_count',
    true
);


DO $$
DECLARE
    v_tag TEXT := current_setting('app.gen_tag');
    v_seed BIGINT := current_setting('app.gen_seed')::BIGINT;
    v_items BIGINT := current_setting('app.gen_items')::BIGINT;
BEGIN
    IF v_tag !~ '^[a-zA-Z0-9]{1,12}$' THEN
        RAISE EXCEPTION
            'tag должен содержать от 1 до 12 латинских букв или цифр';
    END IF;

    IF v_items < 50000 OR
       (v_items > 100000 AND v_items < 3000000) THEN
        RAISE EXCEPTION
            'Разрешено 50000–100000 строк для разработки или минимум 3000000 для нагрузки';
    END IF;

    IF v_seed < 0 OR v_seed > 1000000000 THEN
        RAISE EXCEPTION
            'seed должен находиться в диапазоне 0..1000000000';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM categories
        WHERE left(
            name,
            length('g' || v_tag || '_cat_')
        ) = 'g' || v_tag || '_cat_'
    ) THEN
        RAISE EXCEPTION
            'Набор с tag=% уже существует. Выбери другой tag.',
            v_tag;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM customers
        WHERE left(
            email,
            length('g' || v_tag || '_')
        ) = 'g' || v_tag || '_'
    ) THEN
        RAISE EXCEPTION
            'В customers уже существуют данные с tag=%',
            v_tag;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM sku
        WHERE left(
            article,
            length('g' || v_tag || '_')
        ) = 'g' || v_tag || '_'
    ) THEN
        RAISE EXCEPTION
            'В sku уже существуют данные с tag=%',
            v_tag;
    END IF;
END;
$$;


SELECT setseed(
    (
        current_setting('app.gen_seed')::BIGINT
        % 2000000
    )::DOUBLE PRECISION / 1000000.0 - 1.0
);

-- Расчёт объёмов данных.
CREATE TEMP TABLE gen_params
ON COMMIT DROP
AS
SELECT
    current_setting('app.gen_items')::BIGINT
        AS item_count,

    GREATEST(
        1000,
        CEIL(
            current_setting('app.gen_items')::NUMERIC
            / 100
        )::INTEGER
    ) AS customer_count,

    GREATEST(
        500,
        CEIL(
            current_setting('app.gen_items')::NUMERIC
            / 1000
        )::INTEGER
    ) AS product_count,

    GREATEST(
        10000,
        CEIL(
            current_setting('app.gen_items')::NUMERIC
            / 10
        )::INTEGER
    ) AS order_count,

    20::INTEGER AS category_count,

    5::INTEGER AS sku_per_product,

    TIMESTAMP '2025-01-01 00:00:00'
        AS base_timestamp;


CREATE TEMP TABLE gen_categories_src
ON COMMIT DROP
AS
SELECT
    n,
    'g' || current_setting('app.gen_tag')
        || '_cat_' || n AS name,
    'Generated test category ' || n AS description
FROM generate_series(1, 20) AS gs(n);


CREATE TEMP TABLE gen_customers_src
ON COMMIT DROP
AS
SELECT
    gs.n,

    'g' || current_setting('app.gen_tag')
        || '_customer_' || gs.n
        || '@example.test' AS email,

    '$2b$12$test_generated_password_hash_' || gs.n
        AS password_hash,

    '+7900'
        || LPAD(gs.n::TEXT, 7, '0') AS phone,

    CASE
        WHEN gs.n % 100 = 0 THEN 'admin'
        ELSE 'customer'
    END AS role

FROM generate_series(
    1,
    (SELECT customer_count FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_products_src
ON COMMIT DROP
AS
SELECT
    gs.n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT category_count FROM gen_params)
    )::INTEGER AS category_n,

    'g' || current_setting('app.gen_tag')
        || '_product_' || gs.n AS name,

    'Generated product description ' || gs.n
        AS description,

    CASE gs.n % 8
        WHEN 0 THEN 'Brand A'
        WHEN 1 THEN 'Brand B'
        WHEN 2 THEN 'Brand C'
        WHEN 3 THEN 'Brand D'
        WHEN 4 THEN 'Brand E'
        ELSE 'Generic Brand'
    END AS brand,

    CASE
        WHEN gs.n % 10 < 7 THEN 'published'
        WHEN gs.n % 10 < 9 THEN 'draft'
        ELSE 'archived'
    END AS publication_status

FROM generate_series(
    1,
    (SELECT product_count FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_sku_src
ON COMMIT DROP
AS
SELECT
    p.n * (SELECT sku_per_product FROM gen_params)
        - (SELECT sku_per_product FROM gen_params)
        + v.variant_n AS n,

    p.n AS product_n,

    'g' || current_setting('app.gen_tag')
        || '_sku_'
        || p.n || '_' || v.variant_n AS article,

    CASE v.variant_n % 5
        WHEN 0 THEN 'XS'
        WHEN 1 THEN 'S'
        WHEN 2 THEN 'M'
        WHEN 3 THEN 'L'
        ELSE 'XL'
    END AS size,

    CASE v.variant_n % 4
        WHEN 0 THEN 'black'
        WHEN 1 THEN 'white'
        WHEN 2 THEN 'blue'
        ELSE 'red'
    END AS color,

    (
        500 + FLOOR(
            POWER(random(), 2) * 19500
        )
    )::NUMERIC(10, 2) AS price,

    FLOOR(
        POWER(random(), 2) * 500
    )::INTEGER AS stock_quantity,

    CASE
        WHEN v.variant_n % 10 < 7 THEN 'active'
        WHEN v.variant_n % 10 < 9 THEN 'draft'
        ELSE 'archived'
    END AS status

FROM gen_products_src p
CROSS JOIN generate_series(1, 5) AS v(variant_n);


CREATE TEMP TABLE gen_carts_src
ON COMMIT DROP
AS
SELECT
    gs.n,

    CEIL(gs.n::NUMERIC / 2)::INTEGER
        AS customer_n,

    CASE
        WHEN gs.n % 10 < 5 THEN 'active'
        WHEN gs.n % 10 < 7 THEN 'converted'
        WHEN gs.n % 10 < 9 THEN 'abandoned'
        ELSE 'expired'
    END AS status,

    (
        (SELECT base_timestamp FROM gen_params)
        - FLOOR(random() * 1095) * INTERVAL '1 day'
        + gs.n * INTERVAL '1 microsecond'
    ) AS created_at,

    CASE
        WHEN gs.n % 10 < 5 THEN
            (SELECT base_timestamp FROM gen_params)
            + INTERVAL '30 days'
        ELSE
            (SELECT base_timestamp FROM gen_params)
            - INTERVAL '1 day'
    END AS expires_at

FROM generate_series(
    1,
    (SELECT customer_count * 2 FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_cart_counts
ON COMMIT DROP
AS
SELECT
    c.n AS cart_n,
    1 + FLOOR(random() * 3)::INTEGER AS item_count
FROM gen_carts_src c;


-- Заказы.
CREATE TEMP TABLE gen_orders_src
ON COMMIT DROP
AS
SELECT
    gs.n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT customer_count FROM gen_params)
    )::INTEGER AS customer_n,

    CASE
        WHEN gs.n % 10 < 3 THEN 'created'
        WHEN gs.n % 10 < 5 THEN 'paid'
        WHEN gs.n % 10 < 7 THEN 'shipped'
        WHEN gs.n % 10 < 9 THEN 'delivered'
        ELSE 'cancelled'
    END AS status,

    'Generated Customer '
        || gs.n AS customer_name,

    '+7911'
        || LPAD(gs.n::TEXT, 7, '0') AS customer_phone,

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
        - FLOOR(random() * 1095) * INTERVAL '1 day'
        + gs.n * INTERVAL '1 microsecond'
    ) AS created_at

FROM generate_series(
    1,
    (SELECT order_count FROM gen_params)
) AS gs(n);


INSERT INTO categories (
    name,
    description
)
SELECT
    name,
    description
FROM gen_categories_src
ORDER BY n;


CREATE TEMP TABLE gen_categories_map
ON COMMIT DROP
AS
SELECT
    s.n,
    c.category_id
FROM gen_categories_src s
JOIN categories c
    ON c.name = s.name;


INSERT INTO customers (
    email,
    password_hash,
    phone,
    role
)
SELECT
    email,
    password_hash,
    phone,
    role
FROM gen_customers_src
ORDER BY n;


CREATE TEMP TABLE gen_customers_map
ON COMMIT DROP
AS
SELECT
    s.n,
    c.customer_id
FROM gen_customers_src s
JOIN customers c
    ON c.email = s.email;


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
JOIN gen_categories_map cm
    ON cm.n = p.category_n
ORDER BY p.n;


CREATE TEMP TABLE gen_products_map
ON COMMIT DROP
AS
SELECT
    s.n,
    p.product_id
FROM gen_products_src s
JOIN products p
    ON p.name = s.name;


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
JOIN gen_products_map pm
    ON pm.n = s.product_n
ORDER BY s.n;


CREATE TEMP TABLE gen_sku_map
ON COMMIT DROP
AS
SELECT
    s.n,
    k.sku_id,
    s.price
FROM gen_sku_src s
JOIN sku k
    ON k.article = s.article;


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
    c.expires_at
FROM gen_carts_src c
JOIN gen_customers_map cm
    ON cm.n = c.customer_n
ORDER BY c.n;


CREATE TEMP TABLE gen_carts_map
ON COMMIT DROP
AS
SELECT
    s.n,
    c.cart_id
FROM gen_carts_src s
JOIN gen_customers_map cm
    ON cm.n = s.customer_n
JOIN carts c
    ON c.customer_id = cm.customer_id
   AND c.created_at = s.created_at
   AND c.status = s.status;


CREATE TEMP TABLE gen_cart_items_src
ON COMMIT DROP
AS
SELECT
    c.cart_n,
    slot.n AS slot_n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT COUNT(*) FROM gen_sku_map)
    )::INTEGER AS sku_n,

    1 + FLOOR(random() * 5)::INTEGER AS quantity

FROM gen_cart_counts c
CROSS JOIN LATERAL
    generate_series(1, c.item_count) AS slot(n);


INSERT INTO cart_items (
    cart_id,
    sku_id,
    quantity
)
SELECT
    cm.cart_id,
    sm.sku_id,
    s.quantity
FROM gen_cart_items_src s
JOIN gen_carts_map cm
    ON cm.n = s.cart_n
JOIN gen_sku_map sm
    ON sm.n = s.sku_n;


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
JOIN gen_customers_map cm
    ON cm.n = o.customer_n
ORDER BY o.n;


CREATE TEMP TABLE gen_orders_map
ON COMMIT DROP
AS
SELECT
    src.n,
    o.order_id
FROM gen_orders_src src
JOIN gen_customers_map cm
    ON cm.n = src.customer_n
JOIN orders o
    ON o.customer_id = cm.customer_id
   AND o.created_at = src.created_at
   AND o.status = src.status
   AND o.customer_name = src.customer_name
   AND o.customer_phone = src.customer_phone;


DO $$
DECLARE
    v_expected BIGINT;
    v_actual BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_expected
    FROM gen_orders_src;

    SELECT COUNT(*) INTO v_actual
    FROM gen_orders_map;

    IF v_actual <> v_expected THEN
        RAISE EXCEPTION
            'Ошибка карты заказов: найдено %, ожидалось %',
            v_actual, v_expected;
    END IF;
END;
$$;


-- Генерируем требуемое количество позиций заказа.
CREATE TEMP TABLE gen_order_items_src
ON COMMIT DROP
AS
SELECT
    gs.n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT order_count FROM gen_params)
    )::INTEGER AS order_n,

    1 + FLOOR(
        POWER(random(), 2)
        * (SELECT COUNT(*) FROM gen_sku_map)
    )::INTEGER AS sku_n,

    1 + FLOOR(random() * 5)::INTEGER AS quantity

FROM generate_series(
    1,
    (SELECT item_count FROM gen_params)
) AS gs(n);


CREATE TEMP TABLE gen_order_items_inserted
ON COMMIT DROP
AS
WITH inserted AS (
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
    JOIN gen_orders_map om
        ON om.n = src.order_n
    JOIN gen_sku_map sm
        ON sm.n = src.sku_n
    RETURNING 1
)
SELECT COUNT(*)::BIGINT AS inserted_count
FROM inserted;


DO $$
DECLARE
    v_expected BIGINT :=
        current_setting('app.gen_items')::BIGINT;

    v_source_count BIGINT;
    v_inserted BIGINT;
    v_bad_fk BIGINT;
    v_bad_quantity BIGINT;
    v_bad_price BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO v_source_count
    FROM gen_order_items_src;

    IF v_source_count <> v_expected THEN
        RAISE EXCEPTION
            'Ошибка генерации: подготовлено %, ожидалось %',
            v_source_count, v_expected;
    END IF;

    SELECT inserted_count
    INTO v_inserted
    FROM gen_order_items_inserted;

    IF v_inserted <> v_expected THEN
        RAISE EXCEPTION
            'Ошибка вставки order_items: вставлено %, ожидалось %',
            v_inserted, v_expected;
    END IF;

    SELECT COUNT(*)
    INTO v_bad_fk
    FROM order_items oi
    LEFT JOIN orders o
        ON o.order_id = oi.order_id
    LEFT JOIN sku s
        ON s.sku_id = oi.sku_id
    WHERE o.order_id IS NULL
       OR s.sku_id IS NULL;

    IF v_bad_fk <> 0 THEN
        RAISE EXCEPTION
            'Обнаружено позиций заказа с отсутствующими связями: %',
            v_bad_fk;
    END IF;

    SELECT COUNT(*)
    INTO v_bad_quantity
    FROM order_items
    WHERE quantity <= 0;

    IF v_bad_quantity <> 0 THEN
        RAISE EXCEPTION
            'Обнаружены некорректные количества в order_items: %',
            v_bad_quantity;
    END IF;

    SELECT COUNT(*)
    INTO v_bad_price
    FROM order_items
    WHERE fixed_price < 0;

    IF v_bad_price <> 0 THEN
        RAISE EXCEPTION
            'Обнаружены отрицательные цены в order_items: %',
            v_bad_price;
    END IF;

    RAISE NOTICE
        'Проверка завершена. Вставлено позиций заказа: %',
        v_inserted;
END;
$$;

COMMIT;