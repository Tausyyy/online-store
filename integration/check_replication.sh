#!/usr/bin/env bash
set -euo pipefail

export MSYS_NO_PATHCONV=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
    echo "Ошибка: нет файла .env. Выполните: bash integration/gen_secrets.sh" >&2
    exit 1
fi
set -a
source ./.env
set +a

DC=(docker compose -p replication --project-directory replication --env-file .env
    -f replication/compose.yaml -f integration/replication.secrets.yaml)

P() { "${DC[@]}" exec -T primary psql -U postgres -d online_store -At -v ON_ERROR_STOP=1 -c "$1"; }
R() { "${DC[@]}" exec -T replica psql -U postgres -d online_store -At -v ON_ERROR_STOP=1 -c "$1"; }

step() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
fail() { echo "ОШИБКА: $*" >&2; exit 1; }

wait_streaming() {
    local n
    for _ in $(seq 1 90); do
        n="$(P "SELECT count(*) FROM pg_stat_replication WHERE state = 'streaming'" 2>/dev/null || echo 0)"
        [[ "$n" == "1" ]] && return 0
        sleep 1
    done
    return 1
}

wait_rows_equal() {
    local a b
    for _ in $(seq 1 60); do
        a="$(P "SELECT count(*) FROM lab4_repl_probe" 2>/dev/null || echo x)"
        b="$(R "SELECT count(*) FROM lab4_repl_probe" 2>/dev/null || echo y)"
        [[ "$a" == "$b" && "$a" =~ ^[0-9]+$ ]] && return 0
        sleep 1
    done
    return 1
}

step "1. Чистый запуск primary с паролями из .env"
"${DC[@]}" down -v
"${DC[@]}" up -d --wait primary

step "2. Смена пароля replicator на значение из .env"
rotated=0
for _ in $(seq 1 30); do
    if "${DC[@]}" exec -T primary psql -U postgres -d online_store -v ON_ERROR_STOP=1 -q -f - >/dev/null 2>&1 <<SQL
\set VERBOSITY terse
ALTER ROLE replicator PASSWORD '${REPLICATOR_PASSWORD}';
SQL
    then rotated=1; break; fi
    sleep 2
done
[[ $rotated -eq 1 ]] || fail "не удалось сменить пароль replicator"
echo "Пароль replicator заменён"

step "3. Запуск replica"
"${DC[@]}" up -d replica
wait_streaming || fail "replica не перешла в состояние streaming за 90 секунд"
P "SELECT application_name, state, sync_state FROM pg_stat_replication"
echo "replica в режиме восстановления: $(R 'SELECT pg_is_in_recovery()')"

step "4. Пароли шаблона по умолчанию больше не работают"
if "${DC[@]}" exec -T -e PGPASSWORD=postgres_pass replica psql -h primary -U postgres -d online_store -w -At -c 'SELECT 1' >/dev/null 2>&1; then
    fail "подключение к primary с паролем postgres_pass всё ещё возможно"
fi
echo "OK: postgres_pass отклонён"
if "${DC[@]}" exec -T -e PGPASSWORD=replica_pass replica psql -h primary -U replicator -d online_store -w -At -c 'SELECT 1' >/dev/null 2>&1; then
    fail "подключение к primary с паролем replica_pass всё ещё возможно"
fi
echo "OK: replica_pass отклонён"

step "5. Новая запись на primary появляется на replica"
P "CREATE TABLE lab4_repl_probe (id serial PRIMARY KEY, message text NOT NULL, created_at timestamptz NOT NULL DEFAULT now())" >/dev/null
P "INSERT INTO lab4_repl_probe (message) VALUES ('primary-first')" >/dev/null
wait_rows_equal || fail "запись не появилась на replica"
echo "primary: $(P 'SELECT count(*) FROM lab4_repl_probe') строк, replica: $(R 'SELECT count(*) FROM lab4_repl_probe') строк"
R "SELECT id, message FROM lab4_repl_probe ORDER BY id"

step "6. Запись на replica запрещена"
out="$(R "INSERT INTO lab4_repl_probe (message) VALUES ('write-to-replica')" 2>&1 || true)"
echo "$out" | head -1
echo "$out" | grep -qi "read-only" || fail "replica приняла запись"
echo "OK: replica работает только на чтение"

step "7. Остановка replica и запись на primary во время простоя"
"${DC[@]}" stop replica
P "INSERT INTO lab4_repl_probe (message) VALUES ('during-replica-down-1'), ('during-replica-down-2')" >/dev/null
echo "primary: подключённых реплик = $(P 'SELECT count(*) FROM pg_stat_replication'), строк в таблице = $(P 'SELECT count(*) FROM lab4_repl_probe')"

step "8. Запуск replica и догоняние"
"${DC[@]}" start replica
wait_streaming || fail "replica не вернулась в streaming"
wait_rows_equal || fail "replica не догнала primary"
echo "primary: $(P 'SELECT count(*) FROM lab4_repl_probe') строк, replica: $(R 'SELECT count(*) FROM lab4_repl_probe') строк"

step "9. Сверка содержимого"
SQL_SUM="SELECT count(*) || '|' || md5(string_agg(id || ':' || message, ',' ORDER BY id)) FROM lab4_repl_probe"
a="$(P "$SQL_SUM")"
b="$(R "$SQL_SUM")"
echo "primary: $a"
echo "replica: $b"
[[ "$a" == "$b" ]] || fail "содержимое primary и replica различается"
R "SELECT id, message FROM lab4_repl_probe ORDER BY id"

step "10. Итоговое состояние"
P "SELECT application_name, state, sync_state FROM pg_stat_replication"
echo "ИТОГ: репликация работает, пароли берутся из .env, replica пережила остановку без потери данных"
