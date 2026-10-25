#!/usr/bin/env bash
set -uo pipefail

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

FAIL=0
pass() { echo "PASS: $*"; }
nok()  { echo "FAIL: $*"; FAIL=1; }

docker compose exec -T db bash -c 'umask 077; cat > /tmp/lab4.pgpass' <<PGPASS
*:5432:online_store:lab4_admin:${LAB4_ADMIN_PASSWORD}
*:5432:online_store:lab4_app:${LAB4_APP_PASSWORD}
*:5432:online_store:lab4_analyst:${LAB4_ANALYST_PASSWORD}
*:5432:online_store:postgres:${POSTGRES_PASSWORD}
*:5432:wrongpw_probe:lab4_app:definitely-wrong-password
*:5432:wrongpw_probe:postgres:postgres
PGPASS
trap 'docker compose exec -T db rm -f /tmp/lab4.pgpass >/dev/null 2>&1' EXIT

tcp_psql() {
    local passfile="$1" user="$2" db="$3"
    docker compose exec -T -e "PGPASSFILE=$passfile" db \
        bash -c 'psql -h "$HOSTNAME" -U "$1" -d "$2" -w -At -v ON_ERROR_STOP=1' _ "$user" "$db"
}

echo "=== Подключение по TCP с паролями из .env ==="
for role in lab4_admin lab4_app lab4_analyst postgres; do
    out="$(tcp_psql /tmp/lab4.pgpass "$role" online_store <<<'SELECT current_user' 2>&1)"
    if [[ "$out" == "$role" ]]; then pass "$role подключается по паролю"; else nok "$role не подключился: $out"; fi
done

echo
echo "=== Неверные и отсутствующие пароли ==="
out="$(tcp_psql /tmp/lab4.pgpass lab4_app wrongpw_probe <<<'SELECT 1' 2>&1)"
if [[ "$out" == *"authentication failed"* ]]; then pass "неверный пароль lab4_app отклонён"; else nok "неверный пароль не отклонён: $out"; fi

out="$(tcp_psql /tmp/lab4.pgpass postgres wrongpw_probe <<<'SELECT 1' 2>&1)"
if [[ "$out" == *"authentication failed"* ]]; then pass "пароль postgres по умолчанию (postgres) отклонён"; else nok "пароль postgres по умолчанию принят: $out"; fi

out="$(tcp_psql /tmp/lab4.none lab4_app online_store <<<'SELECT 1' 2>&1)"
if [[ "$out" == *"password"* && "$out" != "1" ]]; then pass "подключение без пароля отклонено"; else nok "подключение без пароля прошло: $out"; fi

echo
echo "=== Приложение не работает с правами суперпользователя ==="
out="$(tcp_psql /tmp/lab4.pgpass lab4_app online_store <<<"SELECT current_setting('is_superuser')" 2>&1)"
if [[ "$out" == "off" ]]; then pass "соединение lab4_app: is_superuser = off"; else nok "is_superuser = $out"; fi

out="$(tcp_psql /tmp/lab4.pgpass lab4_app online_store <<<"SELECT rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls OR rolreplication FROM pg_roles WHERE rolname = 'lab4_app'" 2>&1)"
if [[ "$out" == "f" ]]; then pass "у lab4_app нет привилегированных атрибутов"; else nok "у lab4_app есть привилегированные атрибуты: $out"; fi

out="$(tcp_psql /tmp/lab4.pgpass lab4_app online_store <<<'SET ROLE postgres' 2>&1)"
if [[ "$out" == *"permission denied"* ]]; then pass "lab4_app не может переключиться на postgres"; else nok "SET ROLE postgres: $out"; fi

out="$(tcp_psql /tmp/lab4.pgpass lab4_app online_store <<<'CREATE ROLE lab4_probe_role' 2>&1)"
if [[ "$out" == *"permission denied"* ]]; then pass "lab4_app не может создавать роли"; else nok "CREATE ROLE: $out"; fi

out="$(tcp_psql /tmp/lab4.pgpass lab4_app online_store <<<'DROP TABLE public.orders' 2>&1)"
if [[ "$out" == *"must be owner"* || "$out" == *"permission denied"* ]]; then pass "lab4_app не может удалять таблицы"; else nok "DROP TABLE: $out"; fi

out="$(tcp_psql /tmp/lab4.pgpass lab4_analyst online_store <<<'DELETE FROM public.sku' 2>&1)"
if [[ "$out" == *"permission denied"* ]]; then pass "lab4_analyst не может изменять данные"; else nok "DELETE от analyst: $out"; fi

echo
echo "=== Хранение паролей в базе ==="
out="$(docker compose exec -T db psql -U postgres -d online_store -At -c "SELECT count(*) FROM pg_authid WHERE rolname IN ('postgres','lab4_admin','lab4_app','lab4_analyst') AND rolpassword LIKE 'SCRAM-SHA-256\$%'" 2>&1)"
if [[ "$out" == "4" ]]; then pass "пароли 4 ролей хранятся как SCRAM-SHA-256"; else nok "SCRAM-пароли: $out из 4"; fi

echo
[[ $FAIL -eq 0 ]] && echo "ИТОГ: проверки подключений пройдены" || echo "ИТОГ: есть замечания"
exit $FAIL
