-- Проверка совместимости UP с данными, допустимыми исходной схемой.
-- Запускать ПОСЛЕ create_tables.sql.sql и ДО 001_add_constraints.up.sql.
INSERT INTO categories(name, description)
VALUES ('Legacy category', 'Allowed by old schema');

INSERT INTO customers(email, password_hash, phone, role)
VALUES ('legacy@example.com', 'legacy-hash', '+79990000999', 'customer');

INSERT INTO orders(
    customer_id, status, customer_name, customer_phone,
    delivery_method, payment_method, created_at
)
VALUES (
    (SELECT customer_id FROM customers WHERE email = 'legacy@example.com'),
    'created', 'Legacy User', '+79990000999',
    'pickup', 'card', NULL
);
