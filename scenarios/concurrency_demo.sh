set -euo pipefail

PSQL="psql -U postgres -d online_store -q -v ON_ERROR_STOP=1"


OLD=$($PSQL -At -c "SELECT stock_quantity FROM sku WHERE article = 'TSH-BLK-M'")
$PSQL -c "UPDATE sku SET stock_quantity = 1 WHERE article = 'TSH-BLK-M'"
echo "Остаток TSH-BLK-M установлен в 1 (был $OLD, вернём в конце)."

$PSQL > /tmp/conc_A.txt 2>&1 <<SQL &
BEGIN;
SELECT 'A: взял блокировку, остаток = ' || stock_quantity AS msg FROM sku WHERE article = 'TSH-BLK-M' FOR UPDATE;
SELECT pg_sleep(5);
DO \$\$
BEGIN
    UPDATE sku SET stock_quantity = stock_quantity - 1 WHERE article = 'TSH-BLK-M' AND stock_quantity >= 1;
    IF FOUND THEN RAISE NOTICE 'A: покупка удалась'; ELSE RAISE NOTICE 'A: ОТКАЗ - товар закончился'; END IF;
END
\$\$;
COMMIT;
SQL
PID_A=$!

sleep 1


$PSQL > /tmp/conc_B.txt 2>&1 <<SQL &
BEGIN;
SELECT 'B: получил блокировку, остаток = ' || stock_quantity AS msg FROM sku WHERE article = 'TSH-BLK-M' FOR UPDATE;
DO \$\$
BEGIN
    UPDATE sku SET stock_quantity = stock_quantity - 1 WHERE article = 'TSH-BLK-M' AND stock_quantity >= 1;
    IF FOUND THEN RAISE NOTICE 'B: покупка удалась'; ELSE RAISE NOTICE 'B: ОТКАЗ - товар закончился'; END IF;
END
\$\$;
COMMIT;
SQL
PID_B=$!

sleep 2

echo
echo "=== Диагностика: кто кого ждёт ==="
$PSQL -c "SELECT pid, pg_blocking_pids(pid) AS ждёт_pid, wait_event_type, wait_event, left(query, 60) AS query
          FROM pg_stat_activity
          WHERE datname = current_database() AND wait_event_type = 'Lock'"

wait $PID_A
wait $PID_B

echo "=== Вывод покупателя A ==="
cat /tmp/conc_A.txt
echo "=== Вывод покупателя B ==="
cat /tmp/conc_B.txt

echo "=== Итоговый остаток (должен быть 0, а не отрицательный) ==="
$PSQL -c "SELECT article, stock_quantity FROM sku WHERE article = 'TSH-BLK-M'"


$PSQL -c "UPDATE sku SET stock_quantity = $OLD WHERE article = 'TSH-BLK-M'"
echo "Остаток возвращён: $OLD."