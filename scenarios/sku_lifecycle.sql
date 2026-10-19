\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
    v_sku_id BIGINT;
    v_locked_sku_id BIGINT;
    v_status TEXT;
    v_rows INTEGER;
BEGIN
    SELECT sku_id
    INTO v_sku_id
    FROM sku
    WHERE article = 'JNS-BLU-32'
    FOR UPDATE;

    IF v_sku_id IS NULL THEN
        RAISE EXCEPTION 'SKU JNS-BLU-32 не найден';
    END IF;

    SELECT sku_id
    INTO v_locked_sku_id
    FROM sku
    WHERE sku_id = v_sku_id
    FOR UPDATE;

    SELECT status
    INTO v_status
    FROM sku
    WHERE sku_id = v_sku_id;

    IF v_status <> 'draft' THEN
        RAISE EXCEPTION 'Ожидался статус draft, текущий статус: %', v_status;
    END IF;

    UPDATE sku
    SET status = 'on_sale'
    WHERE sku_id = v_sku_id
      AND status = 'draft'
      AND stock_quantity > 0;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Нельзя перевести SKU в on_sale: проверьте статус и остаток';
    END IF;

    UPDATE sku
    SET status = 'out_of_stock',
        stock_quantity = 0
    WHERE sku_id = v_sku_id
      AND status = 'on_sale'
      AND stock_quantity > 0;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход SKU on_sale -> out_of_stock';
    END IF;

    UPDATE sku
    SET status = 'on_sale',
        stock_quantity = 10
    WHERE sku_id = v_sku_id
      AND status = 'out_of_stock'
      AND stock_quantity = 0;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход SKU out_of_stock -> on_sale';
    END IF;

    UPDATE sku
    SET status = 'archived'
    WHERE sku_id = v_sku_id
      AND status = 'on_sale';

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows <> 1 THEN
        RAISE EXCEPTION 'Недопустимый переход SKU on_sale -> archived';
    END IF;

    SELECT status
    INTO v_status
    FROM sku
    WHERE sku_id = v_sku_id;

    RAISE NOTICE 'SKU ID=%, итоговый статус=%', v_sku_id, v_status;
END $$;

COMMIT;

SELECT sku_id, article, status, stock_quantity
FROM sku
WHERE article = 'JNS-BLU-32';