set -euo pipefail

export MSYS_NO_PATHCONV=1

cd "$(dirname "$0")"
mkdir -p checks/results

PSQL="docker compose exec -T db psql -U postgres -d online_store -v ON_ERROR_STOP=1 -q"

if ! docker info > /dev/null 2>&1; then
    echo "Ошибка: Docker не установлен или не запущен. Запустите Docker Desktop и повторите." >&2
    exit 1
fi

echo "[1/4] Чистая база в Docker"
docker compose down -v
docker compose up -d --wait

echo "[2/4] Схема и миграция 001"
$PSQL -f /project/migrations/create_tables.sql.sql
$PSQL -f /project/migrations/001_add_constraints.up.sql

echo "[3/5] Генератор: seed=52, 3000000 строк в order_items"
$PSQL -v tag=big -v seed=52 -v order_items_count=3000000 \
    -f /project/scripts/data_generator/generate_data.sql

echo "[4/5] Пять бизнес-запросов на нагрузочном наборе"
$PSQL -f /project/queries/business_queries.sql 2>&1 | tee checks/results/business_queries_big.txt

echo "[5/5] Замеры оптимизации до и после"
docker compose exec -T -e DATABASE_URL=postgresql://postgres:postgres@localhost:5432/online_store \
    db bash /project/optimization/run_benchmark.sh 2>&1 | tee checks/results/optimization_benchmark.txt

echo "Готово. Результаты: checks/results/optimization_benchmark.txt, планы: optimization/plans/"
