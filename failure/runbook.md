# Runbook: сбой primary / replica

Команды выполняются из папки `replication/`.

## 1. Определить сбой

```bash
docker compose ps -a
docker compose exec primary pg_isready -U postgres
docker compose exec replica pg_isready -U postgres
```

| Симптом                                                | Сценарий                             |
| ------------------------------------------------------ | ------------------------------------ |
| Запись работает, чтение с replica падает               | A. Replica недоступна                |
| Запись падает (`connection refused`), replica читается | B. Primary недоступна, можно вернуть |
| Primary вернуть нельзя                                 | C. Failover                          |

## 2. Диагностика

```bash
docker compose exec primary psql -U postgres -d online_store -c \
  "SELECT application_name, state, sync_state, replay_lag FROM pg_stat_replication;"

docker compose exec replica psql -U postgres -d online_store -c \
  "SELECT pg_is_in_recovery(), (SELECT status FROM pg_stat_wal_receiver) AS receiver;"

docker compose logs --tail=30 primary
docker compose logs --tail=30 replica
```

В логе replica: `could not connect to the primary server` — primary недоступна;
`started streaming WAL from primary` — связь восстановлена.

## A. Replica недоступна

1. `docker compose start replica`
2. На primary проверить `state = streaming`.
3. Проверить целостность (раздел 3).

Если в логе `requested WAL segment ... has already been removed`: удалить том `replica_data` и
запустить replica заново (`replica.sh` выполнит `pg_basebackup`).

## B. Primary недоступна, можно вернуть

1. Найти причину: `docker compose logs primary`.
2. `docker compose start primary`
3. Replica переподключается сама. На primary проверить `state = streaming`.
4. Проверить целостность (раздел 3).

## C. Failover: повысить replica

1. Остановить старую primary: `docker compose stop primary`. Не запускать её без пересборки
   (split-brain).
2. Повысить replica:
   ```bash
   docker compose exec replica psql -U postgres -d online_store -c "SELECT pg_promote(wait => true);"
   docker compose exec replica psql -U postgres -d online_store -c "SELECT pg_is_in_recovery();"   # ожидается f
   ```
3. Перенаправить запись приложения на новую primary (порт 5434).
4. Проверить запись и целостность (раздел 3, пункты 2–4).
5. Пересобрать старую primary как replica новой:
   ```bash
   pg_basebackup -h <новая primary> -p 5434 -U replicator -D <новый каталог> -Fp -Xs -R
   ```
   Старый каталог данных сохранить отдельно, не удалять до сверки.
6. Сверить записи, сделанные на старой primary после failover, и перенести нужные вручную.

После повышения идентификаторы (`id`) перескакивают вперёд — это нормально.

## 3. Проверка целостности

Выполнить на primary и replica, результаты должны совпасть.

```sql
SELECT 'categories', count(*) FROM categories UNION ALL
SELECT 'customers',  count(*) FROM customers  UNION ALL
SELECT 'products',   count(*) FROM products   UNION ALL
SELECT 'sku',        count(*) FROM sku        UNION ALL
SELECT 'carts',      count(*) FROM carts      UNION ALL
SELECT 'cart_items', count(*) FROM cart_items UNION ALL
SELECT 'orders',     count(*) FROM orders     UNION ALL
SELECT 'order_items', count(*) FROM order_items;

SELECT contype, count(*) FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE n.nspname = 'public' GROUP BY contype ORDER BY contype;

SELECT count(*) FROM order_items oi LEFT JOIN orders o USING (order_id) WHERE o.order_id IS NULL;
SELECT count(*) FROM orders o LEFT JOIN customers c USING (customer_id) WHERE c.customer_id IS NULL;

SELECT count(*) FROM sku WHERE stock_quantity < 0 OR price < 0;
SELECT count(*) FROM order_items WHERE quantity <= 0;
```

Сверка содержимого таблицы: `SELECT md5(string_agg(x::text, '' ORDER BY x::text)) FROM orders x;`
