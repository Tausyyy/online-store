#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$ROOT_DIR/backups"
RESULTS_DIR="$ROOT_DIR/backups"
BACKUP_FILE="$BACKUP_DIR/online_store.dump"
LOG_FILE="$RESULTS_DIR/backup_restore.txt"

SOURCE_DB="online_store"
RESTORE_DB="online_store_restore"
DB_USER="postgres"

mkdir -p "$BACKUP_DIR" "$RESULTS_DIR"

exec > >(tee "$LOG_FILE") 2>&1

echo "--------------------------------------------"
echo "Резервное копирование и восстановление"
echo "Дата: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Исходная БД: $SOURCE_DB"
echo "БД восстановления: $RESTORE_DB"
echo "--------------------------------------------"

if ! docker compose exec -T db pg_isready -U "$DB_USER"; then
    echo "ОШИБКА: PostgreSQL недоступен. Запустите docker compose up -d db"
    exit 1
fi

if ! docker compose exec -T db psql -U "$DB_USER" -d "$SOURCE_DB" \
    -Atqc "SELECT 1" >/dev/null; then
    echo "ОШИБКА: исходная БД $SOURCE_DB недоступна"
    exit 1
fi

echo
echo "1. Создание резервной копии"

docker compose exec -T db pg_dump \
    -U "$DB_USER" \
    -d "$SOURCE_DB" \
    -Fc > "$BACKUP_FILE"

if [[ ! -s "$BACKUP_FILE" ]]; then
    echo "ОШИБКА: файл резервной копии отсутствует или пуст"
    exit 1
fi

echo "Файл: $BACKUP_FILE"
du -h "$BACKUP_FILE"

echo
echo "2. Проверка архива"

docker compose exec -T db pg_restore -l < "$BACKUP_FILE" \
    > /dev/null

echo "Архив читается pg_restore."

echo
echo "3. Подготовка чистой БД для восстановления"
echo "Будет пересоздана только БД $RESTORE_DB."

docker compose exec -T db dropdb \
    --if-exists -U "$DB_USER" "$RESTORE_DB"

docker compose exec -T db createdb \
    -U "$DB_USER" "$RESTORE_DB"

echo
echo "4. Восстановление"

docker compose exec -T db pg_restore \
    -U "$DB_USER" \
    --exit-on-error \
    --no-owner \
    --no-privileges \
    -d "$RESTORE_DB" < "$BACKUP_FILE"

echo "Восстановление завершено без ошибок."

read -r -d '' ROW_COUNTS_SQL <<'SQL' || true
SELECT 'cart_items', COUNT(*) FROM public.cart_items
UNION ALL SELECT 'carts', COUNT(*) FROM public.carts
UNION ALL SELECT 'categories', COUNT(*) FROM public.categories
UNION ALL SELECT 'customers', COUNT(*) FROM public.customers
UNION ALL SELECT 'order_items', COUNT(*) FROM public.order_items
UNION ALL SELECT 'orders', COUNT(*) FROM public.orders
UNION ALL SELECT 'products', COUNT(*) FROM public.products
UNION ALL SELECT 'schema_migrations', COUNT(*) FROM public.schema_migrations
UNION ALL SELECT 'sku', COUNT(*) FROM public.sku
ORDER BY 1;
SQL

echo
echo "5. Сравнение количества записей"

SOURCE_COUNTS="$(docker compose exec -T db psql \
    -U "$DB_USER" -d "$SOURCE_DB" -At -F '|' -c "$ROW_COUNTS_SQL")"

RESTORE_COUNTS="$(docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" -At -F '|' -c "$ROW_COUNTS_SQL")"

echo "Исходная БД:"
printf '%s\n' "$SOURCE_COUNTS"

echo
echo "Восстановленная БД:"
printf '%s\n' "$RESTORE_COUNTS"

if [[ "$SOURCE_COUNTS" != "$RESTORE_COUNTS" ]]; then
    echo "ОШИБКА: количество записей отличается!"
    diff -u <(printf '%s\n' "$SOURCE_COUNTS") \
            <(printf '%s\n' "$RESTORE_COUNTS") || true
    exit 1
fi

echo "Количество записей совпадает во всех 9 таблицах."

echo
echo "6. Сравнение ограничений"

read -r -d '' CONSTRAINTS_SQL <<'SQL' || true
SELECT contype, COUNT(*)
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public'
GROUP BY contype
ORDER BY contype;
SQL

SOURCE_CONSTRAINTS="$(docker compose exec -T db psql \
    -U "$DB_USER" -d "$SOURCE_DB" -At -F '|' -c "$CONSTRAINTS_SQL")"

RESTORE_CONSTRAINTS="$(docker compose exec -T db psql \
    -U "$DB_USER" -d "$RESTORE_DB" -At -F '|' -c "$CONSTRAINTS_SQL")"

echo "Исходная БД:"
printf '%s\n' "$SOURCE_CONSTRAINTS"

echo
echo "Восстановленная БД:"
printf '%s\n' "$RESTORE_CONSTRAINTS"

if [[ "$SOURCE_CONSTRAINTS" != "$RESTORE_CONSTRAINTS" ]]; then
    echo "ОШИБКА: количество ограничений отличается!"
    exit 1
fi

echo "Количество ограничений совпадает."

echo
echo "Резервная копия успешно создана и восстановлена"
echo "Резервная копия: $BACKUP_FILE"
echo "Результаты проверок: $LOG_FILE"
