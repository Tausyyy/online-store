CREATE TABLE IF NOT EXISTS audit_log (
    audit_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    txid            BIGINT      NOT NULL DEFAULT pg_current_xact_id()::text::bigint,
    db_user         TEXT        NOT NULL,
    app_customer_id TEXT,
    client_addr     INET        DEFAULT inet_client_addr(),
    table_name      TEXT        NOT NULL,
    operation       TEXT        NOT NULL,
    row_pk          TEXT,
    changed_columns TEXT[],
    old_data        JSONB,
    new_data        JSONB
);

CREATE INDEX IF NOT EXISTS idx_audit_log_table_time ON audit_log (table_name, occurred_at);
CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log (db_user);

REVOKE ALL ON audit_log FROM PUBLIC;
GRANT SELECT ON audit_log TO lab4_admin;

CREATE OR REPLACE FUNCTION audit_row_change() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    v_old     JSONB;
    v_new     JSONB;
    v_changed TEXT[];
    v_pk      TEXT;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new := to_jsonb(NEW);
    END IF;

    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(n.key ORDER BY n.key)
          INTO v_changed
          FROM jsonb_each(v_new) AS n(key, value)
          LEFT JOIN jsonb_each(v_old) AS o(key, value) ON o.key = n.key
         WHERE n.value IS DISTINCT FROM o.value;
    END IF;

    v_pk := COALESCE(v_new, v_old) ->> TG_ARGV[0];

    INSERT INTO audit_log (
        db_user, app_customer_id, table_name, operation,
        row_pk, changed_columns, old_data, new_data
    )
    VALUES (
        COALESCE(NULLIF(current_setting('role'), 'none'), session_user),
        NULLIF(current_setting('app.customer_id', true), ''),
        TG_TABLE_NAME,
        TG_OP,
        v_pk,
        v_changed,
        v_old - 'password_hash',
        v_new - 'password_hash'
    );

    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION audit_truncate() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    INSERT INTO audit_log (db_user, app_customer_id, table_name, operation)
    VALUES (
        COALESCE(NULLIF(current_setting('role'), 'none'), session_user),
        NULLIF(current_setting('app.customer_id', true), ''),
        TG_TABLE_NAME,
        'TRUNCATE'
    );
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION audit_log_protect() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'audit_log доступна только для добавления записей (операция %)', TG_OP
        USING ERRCODE = 'raise_exception';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_log_no_change ON audit_log;
CREATE TRIGGER trg_audit_log_no_change
    BEFORE UPDATE OR DELETE ON audit_log
    FOR EACH ROW EXECUTE FUNCTION audit_log_protect();

DROP TRIGGER IF EXISTS trg_audit_log_no_truncate ON audit_log;
CREATE TRIGGER trg_audit_log_no_truncate
    BEFORE TRUNCATE ON audit_log
    FOR EACH STATEMENT EXECUTE FUNCTION audit_log_protect();

DROP TRIGGER IF EXISTS trg_audit_orders_insert ON orders;
CREATE TRIGGER trg_audit_orders_insert
    AFTER INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('order_id');

DROP TRIGGER IF EXISTS trg_audit_orders_update ON orders;
CREATE TRIGGER trg_audit_orders_update
    AFTER UPDATE ON orders
    FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION audit_row_change('order_id');

DROP TRIGGER IF EXISTS trg_audit_orders_delete ON orders;
CREATE TRIGGER trg_audit_orders_delete
    AFTER DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('order_id');

DROP TRIGGER IF EXISTS trg_audit_orders_truncate ON orders;
CREATE TRIGGER trg_audit_orders_truncate
    AFTER TRUNCATE ON orders
    FOR EACH STATEMENT EXECUTE FUNCTION audit_truncate();

DROP TRIGGER IF EXISTS trg_audit_order_items_update ON order_items;
CREATE TRIGGER trg_audit_order_items_update
    AFTER UPDATE ON order_items
    FOR EACH ROW WHEN (OLD.* IS DISTINCT FROM NEW.*)
    EXECUTE FUNCTION audit_row_change('order_item_id');

DROP TRIGGER IF EXISTS trg_audit_order_items_delete ON order_items;
CREATE TRIGGER trg_audit_order_items_delete
    AFTER DELETE ON order_items
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('order_item_id');

DROP TRIGGER IF EXISTS trg_audit_order_items_truncate ON order_items;
CREATE TRIGGER trg_audit_order_items_truncate
    AFTER TRUNCATE ON order_items
    FOR EACH STATEMENT EXECUTE FUNCTION audit_truncate();

DROP TRIGGER IF EXISTS trg_audit_sku_update ON sku;
CREATE TRIGGER trg_audit_sku_update
    AFTER UPDATE ON sku
    FOR EACH ROW WHEN (OLD.price IS DISTINCT FROM NEW.price OR OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION audit_row_change('sku_id');

DROP TRIGGER IF EXISTS trg_audit_sku_delete ON sku;
CREATE TRIGGER trg_audit_sku_delete
    AFTER DELETE ON sku
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('sku_id');

DROP TRIGGER IF EXISTS trg_audit_customers_insert ON customers;
CREATE TRIGGER trg_audit_customers_insert
    AFTER INSERT ON customers
    FOR EACH ROW WHEN (NEW.role <> 'customer')
    EXECUTE FUNCTION audit_row_change('customer_id');

DROP TRIGGER IF EXISTS trg_audit_customers_update ON customers;
CREATE TRIGGER trg_audit_customers_update
    AFTER UPDATE ON customers
    FOR EACH ROW WHEN (
        OLD.email         IS DISTINCT FROM NEW.email OR
        OLD.role          IS DISTINCT FROM NEW.role OR
        OLD.password_hash IS DISTINCT FROM NEW.password_hash
    )
    EXECUTE FUNCTION audit_row_change('customer_id');

DROP TRIGGER IF EXISTS trg_audit_customers_delete ON customers;
CREATE TRIGGER trg_audit_customers_delete
    AFTER DELETE ON customers
    FOR EACH ROW EXECUTE FUNCTION audit_row_change('customer_id');
