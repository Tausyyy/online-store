\set ON_ERROR_STOP on


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
    id BIGINT PRIMARY KEY,
    customer_code TEXT NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL
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


CREATE TEMP TABLE benchmark_bulk (
    id BIGINT,
    customer_code TEXT,
    amount NUMERIC(10, 2),
    created_at TIMESTAMP
) ON COMMIT DROP;


CREATE TEMP TABLE benchmark_row (
    id BIGINT,
    customer_code TEXT,
    amount NUMERIC(10, 2),
    created_at TIMESTAMP
) ON COMMIT DROP;


CREATE TEMP TABLE benchmark_results (
    method TEXT NOT NULL,
    repetition INTEGER NOT NULL,
    inserted_rows BIGINT NOT NULL,
    elapsed_ms NUMERIC(14, 3) NOT NULL
) ON COMMIT DROP;


DO $$
DECLARE
    v_rep INTEGER;
    v_started TIMESTAMP;
    v_finished TIMESTAMP;
    v_count BIGINT;
BEGIN
    FOR v_rep IN 1..3 LOOP

        TRUNCATE TABLE benchmark_bulk;

        v_started := clock_timestamp();

        INSERT INTO benchmark_bulk (
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

        v_finished := clock_timestamp();

        SELECT COUNT(*)
        INTO v_count
        FROM benchmark_bulk;

        INSERT INTO benchmark_results (
            method,
            repetition,
            inserted_rows,
            elapsed_ms
        )
        VALUES (
            'INSERT_SELECT',
            v_rep,
            v_count,
            EXTRACT(
                EPOCH FROM (v_finished - v_started)
            ) * 1000
        );

    END LOOP;
END;
$$;


DO $$
DECLARE
    v_rep INTEGER;
    v_started TIMESTAMP;
    v_finished TIMESTAMP;
    v_count BIGINT;
    v_row RECORD;
BEGIN
    FOR v_rep IN 1..3 LOOP

        TRUNCATE TABLE benchmark_row;

        v_started := clock_timestamp();

        FOR v_row IN
            SELECT
                id,
                customer_code,
                amount,
                created_at
            FROM benchmark_source
            ORDER BY id
        LOOP
            INSERT INTO benchmark_row (
                id,
                customer_code,
                amount,
                created_at
            )
            VALUES (
                v_row.id,
                v_row.customer_code,
                v_row.amount,
                v_row.created_at
            );
        END LOOP;

        v_finished := clock_timestamp();

        SELECT COUNT(*)
        INTO v_count
        FROM benchmark_row;

        INSERT INTO benchmark_results (
            method,
            repetition,
            inserted_rows,
            elapsed_ms
        )
        VALUES (
            'ROW_BY_ROW',
            v_rep,
            v_count,
            EXTRACT(
                EPOCH FROM (v_finished - v_started)
            ) * 1000
        );

    END LOOP;
END;
$$;


SELECT
    method,
    repetition,
    inserted_rows,
    elapsed_ms
FROM benchmark_results
ORDER BY method, repetition;


SELECT
    method,
    MAX(inserted_rows) AS inserted_rows,
    ROUND(
        percentile_cont(0.5)
        WITHIN GROUP (ORDER BY elapsed_ms)::NUMERIC,
        3
    ) AS median_ms
FROM benchmark_results
GROUP BY method
ORDER BY median_ms;


WITH medians AS (
    SELECT
        method,
        percentile_cont(0.5)
            WITHIN GROUP (ORDER BY elapsed_ms) AS median_ms
    FROM benchmark_results
    GROUP BY method
)
SELECT
    MAX(
        CASE
            WHEN method = 'INSERT_SELECT'
            THEN median_ms
        END
    ) AS insert_select_median_ms,

    MAX(
        CASE
            WHEN method = 'ROW_BY_ROW'
            THEN median_ms
        END
    ) AS row_by_row_median_ms,

    ROUND(
        (
            MAX(
                CASE
                    WHEN method = 'ROW_BY_ROW'
                    THEN median_ms
                END
            )
            /
            NULLIF(
                MAX(
                    CASE
                        WHEN method = 'INSERT_SELECT'
                        THEN median_ms
                    END
                ),
                0
            )
        )::NUMERIC,
        2
    ) AS row_by_row_is_slower_times

FROM medians;


COMMIT;