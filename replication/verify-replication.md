# Сценарий проверки репликации PostgreSQL

## 1. Запуск контейнеров

В терминале из папки `replication` выполнить:

``` bash
docker compose up -d
docker compose ps
```

Убедиться, что контейнер `replication-primary` работает, а контейнер
`replication-replica` запущен.

## 2. Проверка подключения реплики

На primary выполнить:

``` bash
docker compose exec primary psql -U postgres -d online_store -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```

Ожидаемый результат: состояние репликации `streaming`.

## 3. Проверка передачи новой записи

Создать таблицу на primary:

``` bash
docker compose exec primary psql -U postgres -d online_store -c "CREATE TABLE IF NOT EXISTS test_records (id SERIAL PRIMARY KEY, message TEXT);"
```

Добавить запись на primary:

``` bash
docker compose exec primary psql -U postgres -d online_store -c "INSERT INTO test_records (message) VALUES ('Проверка репликации');"
```

Проверить запись на replica:

``` bash
docker compose exec replica psql -U postgres -d online_store -c "SELECT * FROM test_records ORDER BY id;"
```

Ожидаемый результат: запись `Проверка репликации` отображается на
replica.

## 4. Эксперимент с остановкой replica

Остановить replica:

``` bash
docker compose stop replica
```

Добавить новую запись на primary:

``` bash
docker compose exec primary psql -U postgres -d online_store -c "INSERT INTO test_records (message) VALUES ('Запись во время остановки');"
```

Запустить replica снова:

``` bash
docker compose start replica
```

Проверить состояние репликации:

``` bash
docker compose logs --tail=20 replica
```

Проверить данные на replica:

``` bash
docker compose exec replica psql -U postgres -d online_store -c "SELECT * FROM test_records ORDER BY id;"
```

Ожидаемый результат: после восстановления replica содержит запись,
добавленную на primary во время остановки.

## 5. Завершение проверки

Проверить итоговое состояние репликации:

``` bash
docker compose exec primary psql -U postgres -d online_store -c "SELECT application_name, state, sync_state FROM pg_stat_replication;"
```

Успешный результат: реплика подключена, состояние --- `streaming`, а
записи, созданные на primary, доступны на replica.
