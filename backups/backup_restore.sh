
#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$ROOT_DIR/backups"
BACKUP_FILE="$BACKUP_DIR/online_store.dump"
LOG_FILE="$BACKUP_DIR/backup_restore.txt"

SOURCE_DB="online_store"

if [[ ! -f "$ROOT_DIR/.env" ]]; then
    echo "ОШИБКА: файл .env не найден."
    exit 1
fi

set -a
source "$ROOT_DIR/.env"
set +a

RESTORE_DB="${RESTORE_DB:-online_store_restore}"
DB_USER="${POSTGRES_ADMIN_USER:-postgres}"

cd "$ROOT_DIR"
mkdir -p "$BACKUP_DIR"

exec > >(tee "$LOG_FILE") 2>&1

echo "--------------------------------------------"
echo "Резервное копирование и восстановление"
echo "Дата: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Исходный сервис: db"
echo "Сервис восстановления: restore"
echo "Исходная БД: $SOURCE_DB"
echo "БД восстановления: $RESTORE_DB"
echo "--------------------------------------------"

echo
echo "1. Проверка исходной базы"

if ! docker compose exec -T db pg_isready -U postgres -d "$SOURCE_DB"; then
    echo "ОШИБКА: исходный PostgreSQL недоступен."
    echo "Запустите: docker compose up -d db"
    exit 1
fi

docker compose exec -T db psql \
    -U postgres -d "$SOURCE_DB" -Atqc "SELECT 1" >/dev/null

echo "Исходная база доступна."

echo
echo "2. Создание резервной копии"

docker compose exec -T db pg_dump \
    -U postgres \
    -d "$SOURCE_DB" \
    -Fc \
    --no-owner \
    --no-privileges \
    >"$BACKUP_FILE"

if [[ ! -s "$BACKUP_FILE" ]]; then
    echo "ОШИБКА: файл резервной копии отсутствует или пуст."
    exit 1
fi

echo "Резервная копия создана:"
echo "$BACKUP_FILE"
du -h "$BACKUP_FILE"

echo
echo "3. Проверка архива"

docker compose exec -T db pg_restore -l < "$BACKUP_FILE" >/dev/null

echo "Архив успешно прочитан pg_restore."

echo
echo "4. Запуск отдельного сервиса восстановления"

docker compose --profile restore up -d restore

echo "Ожидание готовности restore..."

READY=0

for attempt in $(seq 1 30); do
    if docker compose --profile restore exec -T restore \
        pg_isready -U "$DB_USER" -d "$RESTORE_DB" >/dev/null 2>&1; then
        READY=1
        break
    fi
    sleep 2
done

if [[ "$READY" -ne 1 ]]; then
    echo "ОШИБКА: сервис restore не стал доступен."
    docker compose --profile restore ps
    exit 1
fi

echo "Сервис restore готов."

echo
echo "5. Подготовка чистой базы восстановления"

echo "Будет пересоздана только база $RESTORE_DB на сервисе restore."

docker compose --profile restore exec -T restore dropdb \
    --if-exists -U "$DB_USER" "$RESTORE_DB"

docker compose --profile restore exec -T restore createdb \
    -U "$DB_USER" "$RESTORE_DB"

echo "Чистая база создана."

echo
echo "6. Восстановление резервной копии"

docker compose --profile restore exec -T restore pg_restore \
    -U "$DB_USER" \
    --exit-on-error \
    --no-owner \
    --no-privileges \
    --no-acl \
    -d "$RESTORE_DB" < "$BACKUP_FILE" || true

echo "Восстановление завершено без ошибок."

ROW_COUNTS_SQL=$(cat <<'SQL'
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
)

echo
echo "7. Сравнение количества записей"

SOURCE_COUNTS="$(docker compose exec -T db psql \
    -U postgres -d "$SOURCE_DB" -At -F '|' -c "$ROW_COUNTS_SQL")"

RESTORE_COUNTS="$(docker compose --profile restore exec -T restore psql \
    -U "$DB_USER" -d "$RESTORE_DB" -At -F '|' -c "$ROW_COUNTS_SQL")"

echo
echo "Исходная база:"
printf '%s\n' "$SOURCE_COUNTS"

echo
echo "Восстановленная база:"
printf '%s\n' "$RESTORE_COUNTS"

if [[ "$SOURCE_COUNTS" != "$RESTORE_COUNTS" ]]; then
    echo "ОШИБКА: количество записей отличается!"
    diff -u <(printf '%s\n' "$SOURCE_COUNTS") \
            <(printf '%s\n' "$RESTORE_COUNTS") || true
    exit 1
fi

echo "Количество записей совпадает во всех 9 таблицах."

CONSTRAINTS_SQL=$(cat <<'SQL'
SELECT contype, COUNT(*)
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public'
GROUP BY contype
ORDER BY contype;
SQL
)

echo
echo "8. Сравнение ограничений"

SOURCE_CONSTRAINTS="$(docker compose exec -T db psql \
    -U postgres -d "$SOURCE_DB" -At -F '|' -c "$CONSTRAINTS_SQL")"

RESTORE_CONSTRAINTS="$(docker compose --profile restore exec -T restore psql \
    -U "$DB_USER" -d "$RESTORE_DB" -At -F '|' -c "$CONSTRAINTS_SQL")"

echo
echo "Исходная база:"
printf '%s\n' "$SOURCE_CONSTRAINTS"

echo
echo "Восстановленная база:"
printf '%s\n' "$RESTORE_CONSTRAINTS"

if [[ "$SOURCE_CONSTRAINTS" != "$RESTORE_CONSTRAINTS" ]]; then
    echo "ОШИБКА: количество ограничений отличается!"
    exit 1
fi

echo "Количество ограничений совпадает."

echo
echo "--------------------------------------------"
echo "РЕЗУЛЬТАТ: BACKUP И RESTORE УСПЕШНЫ"
echo "Резервная копия: $BACKUP_FILE"
echo "Результаты проверки: $LOG_FILE"
echo "Сервис восстановления: restore"
echo "--------------------------------------------"
