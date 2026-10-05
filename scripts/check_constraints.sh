#!/usr/bin/env bash
set -euo pipefail

# Скрипт создаёт временную БД, поэтому исходная БД не изменяется.

: "${DATABASE_URL:?Ошибка: задайте DATABASE_URL}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DB="${TEST_DB:-online_store_constraints_ci}"

BASE_URL="${DATABASE_URL%/*}/postgres"
TEST_URL="${DATABASE_URL%/*}/${TEST_DB}"

cleanup() {
    dropdb "$TEST_DB" --if-exists --maintenance-db="$BASE_URL" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "[1/8] Создание чистой БД: $TEST_DB"
dropdb "$TEST_DB" --if-exists --maintenance-db="$BASE_URL" >/dev/null 2>&1 || true
createdb "$TEST_DB" --maintenance-db="$BASE_URL"

echo "[2/8] Исходная схема"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/migrations/create_tables.sql.sql"

echo "[3/8] Тест данных, допустимых исходной схемой"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/tests/legacy_seed.sql"

echo "[4/8] UP: 001_add_constraints"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/migrations/001_add_constraints.up.sql"

echo "[5/8] Проверка структуры и ограничений"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/tests/schema_assertions.sql"

echo "[6/8] Негативные тесты"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/tests/negative_constraints.sql"

echo "[7/8] DOWN + проверка обратимости"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/migrations/001_add_constraints.down.sql"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/tests/down_assertions.sql"

echo "[8/8] Повторный UP после DOWN"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/migrations/001_add_constraints.up.sql"
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f "$ROOT/tests/schema_assertions.sql"

echo "PASS: UP -> checks -> negative tests -> DOWN -> checks -> UP"
