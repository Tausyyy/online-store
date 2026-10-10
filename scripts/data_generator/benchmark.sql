\set ON_ERROR_STOP on
\timing off

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '0';

SELECT set_config(
    'app.benchmark_rows',
    :'benchmark_rows',
    true
);

DO $$
DECLARE
    v_rows BIGINT :=
        current_setting('app.benchmark_rows')::BIGINT;
BEGIN
    IF v_rows < 1000 OR v_rows > 100000 THEN
        RAISE EXCEPTION
            'benchmark_rows должен быть в диапазоне 1000..100000';
    END IF;
END;
$$;


CREATE TEMP TABLE benchmark_source (
    id            BIGINT PRIMARY KEY,
    customer_code TEXT NOT NULL,
    amount        NUMERIC(10, 2) NOT NULL,
    created_at    TIMESTAMP NOT NULL
) ON COMMIT DROP;


INSERT INTO benchmark_source (
    id,
    customer_code,
    amount,
    created_at
)
SELECT
    gs.n,
    'customer_' || (1 + (gs.n % 10000)),
    (100 + (gs.n % 50000))::NUMERIC(10, 2),
    TIMESTAMP '2025-01-01 00:00:00'
        + gs.n * INTERVAL '1 second'
FROM generate_series(
    1,
    current_setting('app.benchmark_rows')::BIGINT
) AS gs(n);


CREATE TEMP TABLE benchmark_insert_target (
    id            BIGINT PRIMARY KEY,
    customer_code TEXT NOT NULL,
    amount        NUMERIC(10, 2) NOT NULL,
    created_at    TIMESTAMP NOT NULL
) ON COMMIT DROP;


CREATE TEMP TABLE benchmark_copy_target (
    id            BIGINT PRIMARY KEY,
    customer_code TEXT NOT NULL,
    amount        NUMERIC(10, 2) NOT NULL,
    created_at    TIMESTAMP NOT NULL
) ON COMMIT DROP;


\copy benchmark_source (id, customer_code, amount, created_at) TO '/tmp/online_store_copy_benchmark.csv' WITH (FORMAT csv, HEADER true)


\echo
\echo '===== INSERT ... SELECT: 5 замеров ====='

TRUNCATE TABLE benchmark_insert_target;

\timing on

INSERT INTO benchmark_insert_target (
    id,
    customer_code,
    amount,
    created_at
)
SELECT
    id,
    customer_code,
    amount,
    created_at
FROM benchmark_source;

\timing off


TRUNCATE TABLE benchmark_insert_target;

\timing on

INSERT INTO benchmark_insert_target (
    id,
    customer_code,
    amount,
    created_at
)
SELECT
    id,
    customer_code,
    amount,
    created_at
FROM benchmark_source;

\timing off


TRUNCATE TABLE benchmark_insert_target;

\timing on

INSERT INTO benchmark_insert_target (
    id,
    customer_code,
    amount,
    created_at
)
SELECT
    id,
    customer_code,
    amount,
    created_at
FROM benchmark_source;

\timing off


TRUNCATE TABLE benchmark_insert_target;

\timing on

INSERT INTO benchmark_insert_target (
    id,
    customer_code,
    amount,
    created_at
)
SELECT
    id,
    customer_code,
    amount,
    created_at
FROM benchmark_source;

\timing off


TRUNCATE TABLE benchmark_insert_target;

\timing on

INSERT INTO benchmark_insert_target (
    id,
    customer_code,
    amount,
    created_at
)
SELECT
    id,
    customer_code,
    amount,
    created_at
FROM benchmark_source;

\timing off


\echo
\echo '===== COPY: 5 замеров ====='

TRUNCATE TABLE benchmark_copy_target;

\timing on

\copy benchmark_copy_target (id, customer_code, amount, created_at) FROM '/tmp/online_store_copy_benchmark.csv' WITH (FORMAT csv, HEADER true)

\timing off


TRUNCATE TABLE benchmark_copy_target;

\timing on

\copy benchmark_copy_target (id, customer_code, amount, created_at) FROM '/tmp/online_store_copy_benchmark.csv' WITH (FORMAT csv, HEADER true)

\timing off


TRUNCATE TABLE benchmark_copy_target;

\timing on

\copy benchmark_copy_target (id, customer_code, amount, created_at) FROM '/tmp/online_store_copy_benchmark.csv' WITH (FORMAT csv, HEADER true)

\timing off


TRUNCATE TABLE benchmark_copy_target;

\timing on

\copy benchmark_copy_target (id, customer_code, amount, created_at) FROM '/tmp/online_store_copy_benchmark.csv' WITH (FORMAT csv, HEADER true)

\timing off


TRUNCATE TABLE benchmark_copy_target;

\timing on

\copy benchmark_copy_target (id, customer_code, amount, created_at) FROM '/tmp/online_store_copy_benchmark.csv' WITH (FORMAT csv, HEADER true)

\timing off


DO $$
DECLARE
    v_expected BIGINT :=
        current_setting('app.benchmark_rows')::BIGINT;

    v_source BIGINT;
    v_insert BIGINT;
    v_copy BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_source
    FROM benchmark_source;

    SELECT COUNT(*) INTO v_insert
    FROM benchmark_insert_target;

    SELECT COUNT(*) INTO v_copy
    FROM benchmark_copy_target;

    IF v_source <> v_expected
       OR v_insert <> v_expected
       OR v_copy <> v_expected THEN
        RAISE EXCEPTION
            'Количество строк не совпадает: source=%, INSERT=%, COPY=%, expected=%',
            v_source, v_insert, v_copy, v_expected;
    END IF;

    IF EXISTS (
        SELECT id, customer_code, amount, created_at
        FROM benchmark_source

        EXCEPT

        SELECT id, customer_code, amount, created_at
        FROM benchmark_insert_target
    ) THEN
        RAISE EXCEPTION 'Данные INSERT отличаются от источника';
    END IF;

    IF EXISTS (
        SELECT id, customer_code, amount, created_at
        FROM benchmark_source

        EXCEPT

        SELECT id, customer_code, amount, created_at
        FROM benchmark_copy_target
    ) THEN
        RAISE EXCEPTION 'Данные COPY отличаются от источника';
    END IF;

    RAISE NOTICE
        'Проверка пройдена: source=%, INSERT=%, COPY=%',
        v_source, v_insert, v_copy;
END;
$$;


SELECT
    'source' AS dataset,
    COUNT(*) AS row_count
FROM benchmark_source

UNION ALL

SELECT
    'INSERT ... SELECT',
    COUNT(*)
FROM benchmark_insert_target

UNION ALL

SELECT
    'COPY',
    COUNT(*)
FROM benchmark_copy_target;


COMMIT;