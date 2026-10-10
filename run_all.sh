#!/usr/bin/env bash
# Запускает всё по порядку на чистой базе в Docker.
# Результаты сохраняются в папку checks/results/.
# Запуск: bash run_all.sh   (на Windows - в Git Bash)

set -euo pipefail

# Нужно для Git Bash на Windows: иначе пути вида /project/... портятся.
export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")"
mkdir -p checks/results

PSQL="docker compose exec -T db psql -U postgres -d online_store -v ON_ERROR_STOP=1 -q"

if ! docker info > /dev/null 2>&1; then
    echo "Ошибка: Docker не установлен или не запущен. Запустите Docker Desktop и повторите." >&2
    exit 1
fi

echo "[1/11] Чистая база в Docker"
docker compose down -v
docker compose up -d --wait

echo "[2/11] Схема и миграция 001"
$PSQL -f /project/migrations/create_tables.sql.sql
$PSQL -f /project/migrations/001_add_constraints.up.sql

echo "[3/11] Небольшой набор данных data/data.sql"
$PSQL -f /project/data/data.sql

echo "[4/11] Генератор: seed=42, 100000 строк в order_items"
$PSQL -v tag=dev -v seed=42 -v order_items_count=100000 \
    -f /project/scripts/data_generator/generate_data.sql

echo "[5/11] Тесты ограничений (на временной базе)"
docker compose exec -T -e DATABASE_URL=postgresql://postgres:postgres@localhost:5432/online_store \
    db bash /project/scripts/check_constraints.sh 2>&1 | tee checks/results/constraints_tests.txt

echo "[6/11] Проверка данных"
$PSQL -f /project/checks/verify.sql 2>&1 | tee checks/results/verify.txt

echo "[7/11] Пять бизнес-запросов"
$PSQL -f /project/queries/business_queries.sql 2>&1 | tee checks/results/business_queries.txt

echo "[8/11] Сравнение загрузки: INSERT ... SELECT и COPY"
$PSQL -v benchmark_rows=100000 -f /project/scripts/data_generator/benchmark.sql 2>&1 \
    | tee checks/results/load_benchmark.txt

echo "[9/11] Транзакция: COMMIT"
$PSQL -f /project/scenarios/transaction_commit.sql 2>&1 | tee checks/results/transaction_commit.txt

echo "[10/11] Транзакция: ROLLBACK"
$PSQL -f /project/scenarios/transaction_rollback.sql 2>&1 | tee checks/results/transaction_rollback.txt

echo "[11/11] Конкурентность: два покупателя, одна футболка (около 8 секунд)"
docker compose exec -T db bash /project/scenarios/concurrency_demo.sh 2>&1 \
    | tee checks/results/concurrency_demo.txt

echo "Готово. Результаты сохранены в checks/results/"