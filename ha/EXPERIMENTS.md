# Эксперименты с отказами Patroni + HAProxy

Все команды выполнять из папки ha:

cd /mnt/d/СУБД/online-store/ha

## Подготовка

Запустить контейнеры:

docker compose up -d
docker compose ps

Проверить кластер:

docker compose exec patroni1 patronictl -c /etc/patroni.yml list

Если patroni1 остановлен, использовать patroni2.

### Запись через HAProxy (порт 5000)

docker compose exec -e PGPASSWORD=postgres_pass client psql -h haproxy -p 5000 -U postgres -d online_store -c "INSERT INTO failure_probe(note) VALUES ('test') RETURNING id"

### Чтение через HAProxy (порт 5001)

docker compose exec -e PGPASSWORD=postgres_pass client psql -h haproxy -p 5001 -U postgres -d online_store -c "SELECT pg_is_in_recovery(), count(*) FROM failure_probe"

В результате:
- f — ответил Primary.
- t — ответила Replica.

## Мониторинг записи (для экспериментов 2 и 3)

Открыть два терминала в папке ha.

**Терминал 1 — мониторинг.**

Запустить цикл и оставить работать:

while true; do
    TIME=$(date +%T)
    RESULT=$(timeout -k 1s 4s docker exec ha-client-1 \
        env PGPASSWORD=postgres_pass PGCONNECT_TIMEOUT=2 \
        psql -w -h haproxy -p 5000 -U postgres \
        -d online_store -Atqc \
        "INSERT INTO failure_probe(note) VALUES ('failover_monitor') RETURNING id" 2>&1)
    CODE=$?

    if [ "$CODE" -eq 0 ]; then
        echo "$TIME | OK    | ID: $RESULT"
    else
        echo "$TIME | ERROR | ${RESULT:-Timeout (код $CODE)}"
    fi

    sleep 1
done

OK — запись прошла.
ERROR — запись временно недоступна.
После переключения OK должен появиться снова.

Остановить цикл: Ctrl+C.

**Терминал 2 — управление кластером.**

Здесь проверять роли, останавливать и запускать узлы.

## Эксперимент 1. Остановка Replica

1. Посмотреть роли:

docker compose exec patroni1 patronictl -c /etc/patroni.yml list

2. Определить узел с ролью Replica.

3. Остановить Replica. Например:

docker compose stop patroni1

4. Проверить запись через порт 5000. Она должна пройти.

5. Подождать 5–6 секунд и проверить чтение через порт 5001:

docker compose exec -e PGPASSWORD=postgres_pass client psql -h haproxy -p 5001 -U postgres -d online_store -c "SELECT pg_is_in_recovery(), count(*) FROM failure_probe"

Ожидается ошибка, если HAProxy обнаружил недоступность Replica.

6. Запустить остановленный узел:

docker compose start patroni1

7. Через 10–30 секунд проверить кластер. Узел должен вернуться как Replica, состояние streaming.

8. Повторить чтение через порт 5001. Оно должно работать.


## Эксперимент 2. Штатная остановка Primary

1. Проверить роли:

docker compose exec patroni1 patronictl -c /etc/patroni.yml list

2. Записать имя текущего Leader.

3. В терминале 1 запустить цикл мониторинга. Дождаться нескольких OK.

4. В терминале 2 остановить текущий Leader. Например:

docker compose stop patroni2

5. Дождаться, когда после ERROR снова появятся OK.

6. Записать время первой ошибки и первой успешной записи. Остановить цикл через Ctrl+C.

7. Проверить кластер через оставшийся узел:

docker compose exec patroni1 patronictl -c /etc/patroni.yml list

Прежняя Replica должна стать Leader.

8. Запустить старый узел:

docker compose start patroni2

9. Через 20–30 секунд проверить кластер. Старый узел должен вернуться как Replica, streaming.

10. Сравнить количество записей:

docker compose exec patroni1 psql -U postgres -d online_store -c "SELECT count(*) FROM failure_probe"

docker compose exec patroni2 psql -U postgres -d online_store -c "SELECT count(*) FROM failure_probe"


## Эксперимент 3. Аварийное завершение Primary

Перед началом оба узла должны работать:
один Leader, второй Replica со статусом streaming.

1. Проверить роли:

docker compose exec patroni1 patronictl -c /etc/patroni.yml list

2. В терминале 1 запустить цикл мониторинга. Дождаться нескольких OK.

3. В терминале 2 аварийно завершить текущий Leader. Например:

docker compose kill patroni2

4. Дождаться, когда после ERROR снова появятся OK.

5. Записать время первой ошибки и первой успешной записи. Остановить цикл через Ctrl+C.

6. Проверить кластер через оставшийся узел. Он должен стать Leader.

7. Запустить аварийно завершённый узел:

docker compose start patroni2

8. Через 20–30 секунд проверить кластер. Возвращённый узел должен стать Replica, streaming.



## Параметры Patroni

| Параметр | Значение |
|---|---:|
| ttl | 20 секунд |
| loop_wait | 5 секунд |
| retry_timeout | 5 секунд |

При штатной остановке Patroni может корректно освободить лидерство.

При аварийном завершении оставшийся узел обнаруживает потерю лидерства через etcd. Поэтому переключение может занять больше времени.

Время восстановления измеряется по циклу: от первой ошибки до первой успешной записи.