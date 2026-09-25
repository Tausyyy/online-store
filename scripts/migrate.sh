#!/usr/bin/env bash
# =========================================================
# Безопасное применение миграций из migrations/*.up.sql.
#
# Использование:
#   ./migrate.sh up       — применить все ещё не применённые миграции
#   ./migrate.sh down     — откатить последнюю применённую миграцию
#   ./migrate.sh status   — показать, что уже применено
#
# Требует переменную окружения DATABASE_URL, например:
#   export DATABASE_URL="postgresql://user:pass@localhost:5432/clothing_store"
#
# ВАЖНО: migrations/create_tables.sql.sql сюда НЕ попадает — маска
# "*.up.sql" его не подхватывает (имя заканчивается на .sql.sql, а не
# .up.sql). Его нужно один раз запустить руками, как и раньше
# (см. README.md — schema (2).sql / create_tables.sql.sql в DBeaver).
# Этот скрипт управляет только пронумерованными миграциями (001_..., 002_...).
# =========================================================

set -euo pipefail

MIGRATIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../migrations" && pwd)"

if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "Ошибка: не задана переменная DATABASE_URL" >&2
    exit 1
fi

cmd="${1:-status}"

case "$cmd" in
    up)
        for f in "$MIGRATIONS_DIR"/*.up.sql; do
            [[ -e "$f" ]] || continue
            version=$(basename "$f" | cut -d'_' -f1)
            applied=$(psql "$DATABASE_URL" -tAc \
                "SELECT 1 FROM schema_migrations WHERE version = '$version'" 2>/dev/null || echo "")
            if [[ "$applied" == "1" ]]; then
                echo "[skip] $version уже применена"
                continue
            fi
            echo "[apply] $(basename "$f")"
            psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "$f"
        done
        ;;
    down)
        last=$(psql "$DATABASE_URL" -tAc \
            "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1")
        if [[ -z "$last" ]]; then
            echo "Нет применённых миграций для отката."
            exit 0
        fi
        down_file="$MIGRATIONS_DIR/${last}_"*".down.sql"
        echo "[rollback] $last"
        psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f $down_file
        ;;
    status)
        psql "$DATABASE_URL" -c \
            "SELECT version, description, applied_at FROM schema_migrations ORDER BY version;"
        ;;
    *)
        echo "Неизвестная команда: $cmd (используйте up | down | status)" >&2
        exit 1
        ;;
esac
