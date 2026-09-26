-- Проверка, что после DOWN схема вернулась к исходной.
BEGIN;

DO $$
DECLARE v_count integer;
BEGIN
    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='categories' AND column_name='name'
      AND is_nullable='YES' AND character_maximum_length=200;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: categories.name не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='customers' AND column_name='email'
      AND is_nullable='YES' AND character_maximum_length=200;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: customers.email не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='customers' AND column_name='password_hash'
      AND is_nullable='YES' AND character_maximum_length=200;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: customers.password_hash не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='customers' AND column_name='role'
      AND is_nullable='YES' AND character_maximum_length=50;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: customers.role не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='products' AND column_name='brand'
      AND character_maximum_length=200;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: products.brand не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='products' AND column_name='publication_status'
      AND character_maximum_length=50;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: products.publication_status не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='sku' AND column_name='article'
      AND character_maximum_length=100;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: sku.article не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='sku' AND column_name='size'
      AND character_maximum_length=50;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: sku.size не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='sku' AND column_name='status'
      AND character_maximum_length=50;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: sku.status не восстановлен'; END IF;

    SELECT count(*) INTO v_count FROM information_schema.columns
    WHERE table_name='orders' AND column_name='customer_name'
      AND character_maximum_length=200;
    IF v_count <> 1 THEN RAISE EXCEPTION 'DOWN: orders.customer_name не восстановлен'; END IF;
END $$;

ROLLBACK;
