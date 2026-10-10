BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001') THEN
        RAISE EXCEPTION 'Сначала нужно применить миграцию 001.';
    END IF;
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = '002') THEN
        RAISE EXCEPTION 'Миграция 002 уже применена. Повторный запуск отменён.';
    END IF;
END $$;

-- Нужен запросам "заказы покупателя" (WHERE customer_id = ...).
CREATE INDEX idx_orders_customer_id ON orders (customer_id);

-- Нужен для перехода от заказа к его позициям (JOIN order_items ON order_id).
CREATE INDEX idx_order_items_order_id ON order_items (order_id);

INSERT INTO schema_migrations (version, description)
VALUES ('002', 'Индексы orders(customer_id) и order_items(order_id)');

COMMIT;
