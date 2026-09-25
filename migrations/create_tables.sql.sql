CREATE TABLE categories (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(200),
    description TEXT
);

-- Покупатели
CREATE TABLE customers (
    customer_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email         VARCHAR(200),
    password_hash VARCHAR(200),
    phone         VARCHAR(20),
    role          VARCHAR(50)
);

-- Товары
CREATE TABLE products (
    product_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_id        BIGINT REFERENCES categories (category_id),
    name               VARCHAR(200),
    description        TEXT,
    brand              VARCHAR(200),
    publication_status VARCHAR(50)
);

-- Варианты товара (SKU)
CREATE TABLE sku (
    sku_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id     BIGINT REFERENCES products (product_id),
    article        VARCHAR(100),
    size           VARCHAR(50),
    color          VARCHAR(50),
    price          NUMERIC,
    stock_quantity INTEGER,
    status         VARCHAR(50)
);

-- Корзины
CREATE TABLE carts (
    cart_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id BIGINT REFERENCES customers (customer_id),
    status      VARCHAR(50),
    created_at  TIMESTAMP,
    expires_at  TIMESTAMP
);

-- Позиции корзины
CREATE TABLE cart_items (
    cart_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cart_id      BIGINT REFERENCES carts (cart_id),
    sku_id       BIGINT REFERENCES sku (sku_id),
    quantity     INTEGER
);

-- Заказы
CREATE TABLE orders (
    order_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id     BIGINT REFERENCES customers (customer_id),
    status          VARCHAR(50),
    customer_name   VARCHAR(200),
    customer_phone  VARCHAR(20),
    delivery_method VARCHAR(50),
    payment_method  VARCHAR(50),
    created_at      TIMESTAMP
);

-- Позиции заказа
CREATE TABLE order_items (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      BIGINT REFERENCES orders (order_id),
    sku_id        BIGINT REFERENCES sku (sku_id),
    quantity      INTEGER,
    fixed_price   NUMERIC
);
