BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '002') THEN
        RAISE EXCEPTION 'Миграция 002 не применена — откатывать нечего.';
    END IF;
END $$;

DROP INDEX idx_order_items_order_id;
DROP INDEX idx_orders_customer_id;

DELETE FROM schema_migrations WHERE version = '002';

COMMIT;
