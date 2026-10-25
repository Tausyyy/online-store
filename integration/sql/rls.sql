CREATE OR REPLACE FUNCTION app_current_customer_id() RETURNS BIGINT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.customer_id', true), '')::bigint
$$;

GRANT EXECUTE ON FUNCTION app_current_customer_id() TO lab4_admin, lab4_app, lab4_analyst;

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items FORCE ROW LEVEL SECURITY;
ALTER TABLE carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE carts FORCE ROW LEVEL SECURITY;
ALTER TABLE cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE cart_items FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orders_admin_all ON orders;
CREATE POLICY orders_admin_all ON orders
    FOR ALL TO lab4_admin
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS orders_analyst_select ON orders;
CREATE POLICY orders_analyst_select ON orders
    FOR SELECT TO lab4_analyst
    USING (true);

DROP POLICY IF EXISTS orders_app_own ON orders;
CREATE POLICY orders_app_own ON orders
    FOR ALL TO lab4_app
    USING (customer_id = app_current_customer_id())
    WITH CHECK (customer_id = app_current_customer_id());

DROP POLICY IF EXISTS order_items_admin_all ON order_items;
CREATE POLICY order_items_admin_all ON order_items
    FOR ALL TO lab4_admin
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS order_items_analyst_select ON order_items;
CREATE POLICY order_items_analyst_select ON order_items
    FOR SELECT TO lab4_analyst
    USING (true);

DROP POLICY IF EXISTS order_items_app_own ON order_items;
CREATE POLICY order_items_app_own ON order_items
    FOR ALL TO lab4_app
    USING (
        EXISTS (
            SELECT 1 FROM orders o
            WHERE o.order_id = order_items.order_id
              AND o.customer_id = app_current_customer_id()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM orders o
            WHERE o.order_id = order_items.order_id
              AND o.customer_id = app_current_customer_id()
        )
    );

DROP POLICY IF EXISTS carts_admin_all ON carts;
CREATE POLICY carts_admin_all ON carts
    FOR ALL TO lab4_admin
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS carts_analyst_select ON carts;
CREATE POLICY carts_analyst_select ON carts
    FOR SELECT TO lab4_analyst
    USING (true);

DROP POLICY IF EXISTS carts_app_own ON carts;
CREATE POLICY carts_app_own ON carts
    FOR ALL TO lab4_app
    USING (customer_id = app_current_customer_id())
    WITH CHECK (customer_id = app_current_customer_id());

DROP POLICY IF EXISTS cart_items_admin_all ON cart_items;
CREATE POLICY cart_items_admin_all ON cart_items
    FOR ALL TO lab4_admin
    USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS cart_items_analyst_select ON cart_items;
CREATE POLICY cart_items_analyst_select ON cart_items
    FOR SELECT TO lab4_analyst
    USING (true);

DROP POLICY IF EXISTS cart_items_app_own ON cart_items;
CREATE POLICY cart_items_app_own ON cart_items
    FOR ALL TO lab4_app
    USING (
        EXISTS (
            SELECT 1 FROM carts c
            WHERE c.cart_id = cart_items.cart_id
              AND c.customer_id = app_current_customer_id()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM carts c
            WHERE c.cart_id = cart_items.cart_id
              AND c.customer_id = app_current_customer_id()
        )
    );
