#!/usr/bin/env bash
# Роль 4: замеры "до" и "после" оптимизации для запросов 1 и 2.
#
# Перед запуском: схема + миграция 001 + данные (generate_data.sql, лучше 3 000 000 строк).
# Запуск:
#   export DATABASE_URL="postgresql://user:pass@localhost:5432/online_store"
#   ./optimization/run_benchmark.sh            # 5 замеров на запрос
#   RUNS=9 ./optimization/run_benchmark.sh     # другое число замеров
#
# Что делает скрипт:
#   1. Если миграция 002 (индексы) уже применена, откатывает её -> состояние "до".
#   2. VACUUM ANALYZE, затем для каждого запроса:
#        - сохраняет план EXPLAIN (ANALYZE, BUFFERS) в optimization/plans/*_before.txt
#        - делает 1 прогревочный запуск и RUNS замеров, считает медиану
#   3. Применяет миграцию 002 (индексы) -> состояние "после", делает ANALYZE.
#   4. Повторяет шаг 2 (запрос 2 уже в переписанном виде) и сохраняет *_after.txt
#   5. Проверяет, что старый и новый запрос 2 вернули одинаковый результат.
#   6. Печатает таблицу с медианами.

set -euo pipefail

: "${DATABASE_URL:?Ошибка: задайте DATABASE_URL}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="$ROOT/optimization"
PLANS="$DIR/plans"
RUNS="${RUNS:-5}"

mkdir -p "$PLANS"

run_sql() { psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qAt "$@"; }

# Время выполнения (мс) одного запуска EXPLAIN ANALYZE.
one_run_ms() {
    run_sql -c "EXPLAIN (ANALYZE) $(cat "$1")" \
        | awk '/Execution Time/ {print $3}'
}

# Медиана RUNS замеров после одного прогревочного запуска.
median_ms() {
    one_run_ms "$1" > /dev/null   # прогрев: данные попадают в кэш
    for _ in $(seq "$RUNS"); do one_run_ms "$1"; done \
        | sort -n \
        | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'
}

# Сохранить полный план EXPLAIN (ANALYZE, BUFFERS) в файл.
save_plan() {
    run_sql -c "EXPLAIN (ANALYZE, BUFFERS) $(cat "$1")" > "$2"
}

# ---------- Состояние "до" ----------
if [[ "$(run_sql -c "SELECT 1 FROM schema_migrations WHERE version = '002'")" == "1" ]]; then
    echo "[0] Миграция 002 уже применена - откатываю, чтобы получить состояние ДО"
    DATABASE_URL="$DATABASE_URL" "$ROOT/scripts/migrate.sh" down
fi

echo "[1] VACUUM ANALYZE (свежая статистика для планировщика)"
run_sql -c "VACUUM ANALYZE"

echo "[2] Замеры ДО оптимизации (медиана из $RUNS запусков)"
save_plan "$DIR/q1.sql"        "$PLANS/q1_before.txt"
save_plan "$DIR/q2_before.sql" "$PLANS/q2_before.txt"
Q1_BEFORE="$(median_ms "$DIR/q1.sql")"
Q2_BEFORE="$(median_ms "$DIR/q2_before.sql")"
run_sql -c "$(sed 's/;[[:space:]]*$//' "$DIR/q2_before.sql")" > /tmp/q2_before_result.txt

# ---------- Оптимизация ----------
echo "[3] Применяю миграцию 002 (индексы)"
DATABASE_URL="$DATABASE_URL" "$ROOT/scripts/migrate.sh" up > /dev/null
run_sql -c "ANALYZE orders" -c "ANALYZE order_items"

# ---------- Состояние "после" ----------
echo "[4] Замеры ПОСЛЕ оптимизации"
save_plan "$DIR/q1.sql"        "$PLANS/q1_after.txt"
save_plan "$DIR/q2_after.sql"  "$PLANS/q2_after.txt"
Q1_AFTER="$(median_ms "$DIR/q1.sql")"
Q2_AFTER="$(median_ms "$DIR/q2_after.sql")"
# Контроль: старый запрос 2 при наличии индексов (должен остаться медленным)
Q2_OLD_WITH_INDEXES="$(median_ms "$DIR/q2_before.sql")"
run_sql -c "$(sed 's/;[[:space:]]*$//' "$DIR/q2_after.sql")" > /tmp/q2_after_result.txt

echo "[5] Проверка: старый и новый запрос 2 возвращают одинаковый результат"
if diff -q /tmp/q2_before_result.txt /tmp/q2_after_result.txt > /dev/null; then
    echo "    OK: результаты совпадают"
else
    echo "    ОШИБКА: результаты различаются!" >&2
    diff /tmp/q2_before_result.txt /tmp/q2_after_result.txt >&2 || true
    exit 1
fi

# ---------- Таблица ----------
ratio() { awk -v a="$1" -v b="$2" 'BEGIN {printf "%.1f", a / b}'; }

echo
echo "| Запрос | Что изменили | До, мс (медиана) | После, мс (медиана) | Ускорение |"
echo "|---|---|---:|---:|---:|"
echo "| Q1: история заказов (customer_id = 15) | индексы (миграция 002) | $Q1_BEFORE | $Q1_AFTER | в $(ratio "$Q1_BEFORE" "$Q1_AFTER") раз |"
echo "| Q2: топ-10 товаров | переписан запрос | $Q2_BEFORE | $Q2_AFTER | в $(ratio "$Q2_BEFORE" "$Q2_AFTER") раз |"
echo "| (контроль) Q2 старый, но с индексами | только индексы | $Q2_BEFORE | $Q2_OLD_WITH_INDEXES | в $(ratio "$Q2_BEFORE" "$Q2_OLD_WITH_INDEXES") раз |"
echo
echo "Планы сохранены в $PLANS"
