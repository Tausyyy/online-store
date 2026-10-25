#!/usr/bin/env bash
set -euo pipefail

export MSYS_NO_PATHCONV=1

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RESULTS_DIR="integration/results"
SKIP_BASE=0
SKIP_REPL=0
WITH_FAILURE=0
ROTATE=0
KEEP_RESULTS=0

usage() {
    cat <<USAGE
Использование: bash integration/run_lab4.sh [параметры]

  --skip-base         не пересоздавать базу (run_all.sh), использовать уже запущенную
  --skip-replication  пропустить primary/replica
  --with-failure      после репликации выполнить failure/failure_experiments.sh
  --rotate-secrets    сгенерировать новые пароли в .env
  --keep-results      не возвращать результаты участников (checks/results, backups, failure/results)
  -h, --help          эта справка
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --skip-base) SKIP_BASE=1 ;;
        --skip-replication) SKIP_REPL=1 ;;
        --with-failure) WITH_FAILURE=1 ;;
        --rotate-secrets) ROTATE=1 ;;
        --keep-results) KEEP_RESULTS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Неизвестный параметр: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ $WITH_FAILURE -eq 1 && $SKIP_REPL -eq 1 ]]; then
    echo "Ошибка: --with-failure требует запущенной репликации (уберите --skip-replication)" >&2
    exit 2
fi

if ! docker info >/dev/null 2>&1; then
    echo "Ошибка: Docker не установлен или не запущен." >&2
    exit 1
fi

mkdir -p "$RESULTS_DIR"

PRESERVE_DIRS=(checks/results backups failure/results)
SNAP="$(mktemp -d)"

snapshot() {
    local d
    for d in "${PRESERVE_DIRS[@]}"; do
        if [[ -d "$d" ]]; then
            mkdir -p "$SNAP/$d"
            cp -a "$d/." "$SNAP/$d/"
        fi
    done
}

restore() {
    local d
    if [[ $KEEP_RESULTS -eq 0 ]]; then
        for d in "${PRESERVE_DIRS[@]}"; do
            if [[ -d "$SNAP/$d" ]]; then
                cp -a "$SNAP/$d/." "$d/"
            fi
        done
    fi
    rm -rf "$SNAP"
}

snapshot
trap restore EXIT

psql_db() { docker compose exec -T db psql -U postgres -d online_store -v ON_ERROR_STOP=1 -q "$@"; }

STEP=0
TOTAL=11
step() {
    STEP=$((STEP + 1))
    printf '\n[%d/%d] %s\n' "$STEP" "$TOTAL" "$*"
}

logged() {
    local name="$1"
    shift
    "$@" 2>&1 | tee "$RESULTS_DIR/$name.txt"
}

step "Секреты: пароли в .env вне Git"
if [[ $ROTATE -eq 1 ]]; then
    bash integration/gen_secrets.sh --force
else
    bash integration/gen_secrets.sh
fi
set -a
source ./.env
set +a

step "Основа проекта: база, схема, данные и проверки (run_all.sh)"
if [[ $SKIP_BASE -eq 1 ]]; then
    echo "Пропущено (--skip-base)"
    psql_db -At -c "SELECT 'База online_store доступна'"
else
    bash run_all.sh
    rm -rf "$RESULTS_DIR/base_checks"
    cp -a checks/results "$RESULTS_DIR/base_checks"
fi

step "Роли участника 1: roles/sql/roles.sql"
role_count="$(psql_db -At -c "SELECT count(*) FROM pg_roles WHERE rolname IN ('lab4_admin','lab4_app','lab4_analyst')")"
if [[ "$role_count" == "3" ]]; then
    echo "Роли уже существуют, создание пропущено"
else
    sed 's/online_store_lab4/online_store/g' roles/sql/roles.sql | psql_db -f -
    echo "Роли созданы"
fi

step "Пароли ролей из .env (в аргументах команд и логах не видны)"
psql_db -f - <<SQL
\set VERBOSITY terse
ALTER ROLE postgres PASSWORD '${POSTGRES_PASSWORD}';
ALTER ROLE lab4_admin PASSWORD '${LAB4_ADMIN_PASSWORD}';
ALTER ROLE lab4_app PASSWORD '${LAB4_APP_PASSWORD}';
ALTER ROLE lab4_analyst PASSWORD '${LAB4_ANALYST_PASSWORD}';
SQL
echo "Пароли postgres, lab4_admin, lab4_app, lab4_analyst заменены"

step "Аудит и RLS: integration/sql/audit.sql, integration/sql/rls.sql"
psql_db -f /project/integration/sql/audit.sql
psql_db -f /project/integration/sql/rls.sql
echo "Триггеры аудита и политики RLS созданы"

step "Проверки: права ролей, аудит, RLS, подключения, секреты"
logged permissions_test psql_db -f /project/roles/sql/permissions_test.sql
logged audit_test psql_db -f /project/integration/sql/audit_test.sql
logged rls_test psql_db -f /project/integration/sql/rls_test.sql
logged connections_test bash integration/check_connections.sh
logged secrets_test bash integration/check_secrets.sh

step "Реальные операции для журнала аудита"
logged audit_demo psql_db -f /project/integration/sql/audit_demo.sql

step "Backup и restore участника 2: backups/backup_restore.sh"
logged backup_restore bash backups/backup_restore.sh

echo
echo "Сверка аудита и RLS после восстановления"
SECURITY_SQL="SELECT 'rls_tables', count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relrowsecurity
UNION ALL SELECT 'policies', count(*) FROM pg_policy
UNION ALL SELECT 'user_triggers', count(*) FROM pg_trigger WHERE NOT tgisinternal
UNION ALL SELECT 'audit_rows', count(*) FROM audit_log
ORDER BY 1"
SRC_SEC="$(docker compose exec -T db psql -U postgres -d online_store -At -F '|' -c "$SECURITY_SQL")"
RST_SEC="$(docker compose exec -T db psql -U postgres -d online_store_restore -At -F '|' -c "$SECURITY_SQL")"
{
    echo "Исходная БД:"
    printf '%s\n' "$SRC_SEC"
    echo "Восстановленная БД:"
    printf '%s\n' "$RST_SEC"
    if [[ "$SRC_SEC" == "$RST_SEC" ]]; then
        echo "ИТОГ: RLS, политики, триггеры и журнал аудита восстановлены полностью"
    else
        echo "ИТОГ: ОШИБКА, состояние безопасности после восстановления отличается"
    fi
    echo "Права ролей в восстановленной БД (backup_restore.sh использует --no-privileges): app SELECT на orders = $(docker compose exec -T db psql -U postgres -d online_store_restore -At -c "SELECT has_table_privilege('lab4_app','public.orders','SELECT')")"
} 2>&1 | tee "$RESULTS_DIR/restore_security_check.txt"
[[ "$SRC_SEC" == "$RST_SEC" ]]

step "Репликация: primary и replica с паролями из .env"
if [[ $SKIP_REPL -eq 1 ]]; then
    echo "Пропущено (--skip-replication)"
else
    logged replication_check bash integration/check_replication.sh
fi

step "Эксперименты с отказами участника 4: failure/failure_experiments.sh"
if [[ $WITH_FAILURE -eq 1 ]]; then
    bash failure/failure_experiments.sh
    cp failure/results/failure_experiments_raw.txt "$RESULTS_DIR/failure_experiments_raw.txt"
else
    echo "Пропущено (запуск: --with-failure)"
fi

step "Готово"
echo "Результаты каждого шага: $RESULTS_DIR/"
ls -1 "$RESULTS_DIR"
if [[ $KEEP_RESULTS -eq 0 ]]; then
    echo "Файлы участников (checks/results, backups, failure/results) возвращены в исходное состояние"
fi
