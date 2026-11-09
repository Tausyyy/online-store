# Patroni + HAProxy

## Идея в трёх строках

- **Patroni** следит за PostgreSQL. Если primary упал, он сам повышает replica 
- **HAProxy** стоит перед базами и всегда направляет запись на текущий primary, а чтение на replica. Приложению не надо менять адрес после сбоя.
- **etcd** хранит, кто сейчас primary. Без него Patroni не работает.

```
 приложение ─► HAProxy ─┬─ :5000 запись ─► текущий primary
                        └─ :5001 чтение ─► replica
                                 patroni1 / patroni2  (+ etcd)
```

## Файлы

| Файл | Зачем |
|---|---|
| `compose.yaml` | какие контейнеры запускаем: etcd, два узла, haproxy, client |
| `patroni/Dockerfile` | PostgreSQL + установленный Patroni |
| `patroni/patroni1.yml`, `patroni2.yml` | настройки Patroni (отличаются только именем узла) |
| `haproxy/haproxy.cfg` | правила: кого считать primary, кого replica |
| `EXPERIMENTS.md` | пошаговые эксперименты и таблица для отчёта |

## Запуск

```bash
docker compose up -d --build
```

Подождите около 30 секунд и посмотрите состояние:

```bash
docker compose exec patroni1 patronictl -c /etc/patroni.yml list
```

Должны быть два узла: один `Leader`, другой `Replica` (state `streaming`).
Страница HAProxy: http://127.0.0.1:7000

Создайте базу и таблицу для проб (команды выполняются через HAProxy, он сам найдёт primary):

```bash
docker compose exec -e PGPASSWORD=postgres_pass client psql -h haproxy -p 5000 -U postgres -c "CREATE DATABASE online_store"
docker compose exec -e PGPASSWORD=postgres_pass client psql -h haproxy -p 5000 -U postgres -d online_store -c "CREATE TABLE failure_probe (id serial PRIMARY KEY, note text)"
```

Схему нашего магазина можно загрузить так (из корня репозитория проекта):

```bash
docker compose -f ha/compose.yaml exec -T -e PGPASSWORD=postgres_pass client psql -h haproxy -p 5000 -U postgres -d online_store < migrations/create_tables.sql.sql
```

Остановить и стереть всё: `docker compose down -v`.

## Вопросы, которые могут нам помочь :)

- **Что делает Patroni?** Следит за узлами, выбирает лидера через etcd и сам повышает replica при сбое.
- **Что делает HAProxy?** Спрашивает у Patroni, кто primary, и направляет туда запись. Это единая точка входа.
- **Зачем etcd?** Чтобы узлы договорились, кто лидер, и не получилось двух primary сразу.
- **Почему при `kill` простой дольше, чем при `stop`?** При `stop` Patroni успевает освободить роль лидера, при `kill` ждёт, пока истечёт `ttl` (20 с).
- **Что с бывшим primary после возврата?** Patroni откатывает его через `pg_rewind` и делает replica, поэтому split-brain не возникает.
- **Что не решено?** Репликация асинхронная, последние транзакции при аварии могут потеряться. etcd и HAProxy в одном экземпляре.

