# Эксперименты с отказами primary и replica

## Среда

- PostgreSQL 16.15, потоковая асинхронная репликация: primary (порт 5433), replica (порт 5434).
- Настройки как в `replication/compose.yaml`: `wal_level=replica`, `max_wal_senders=5`, replica создана `pg_basebackup -Xs -R`, пользователь `replicator`, слота репликации нет.
- Данные: схема, ограничения и `data/data.sql` проекта + таблица `failure_probe`.
- Приложение имитирует скрипт `failure_experiments.sh`: пишет на primary, читает с replica, фиксирует OK/FAIL.
- Экземпляры запущены без Docker (`MODE=local`). Для Docker: `bash failure/failure_experiments.sh` (режим по умолчанию).
- Сырые логи: `results/failure_experiments_raw.txt`, `results/failover_rebuild.txt`.

Проверка целостности после каждого эксперимента: число строк и md5 содержимого всех таблиц на primary и replica, ограничения (`c=5, f=8, p=10, u=3`), записи без родителя по внешним ключам.

## E0. Исходное состояние

| Проверка | Результат |
|---|---|
| `pg_stat_replication` на primary | `streaming / async` |
| replica | `pg_is_in_recovery = t`, walreceiver `streaming` |
| Запись на primary → чтение с replica | запись видна, все таблицы совпали |

## E1. Остановка replica

| Действие | Результат |
|---|---|
| Остановка replica | primary продолжает работать |
| 3 записи на primary | `OK` |
| `pg_stat_replication` | пусто |
| Чтение с replica | `FAIL`, соединение не устанавливается |
| Запуск replica | `started streaming WAL from primary`, догнала сама (простой 0,3 с) |
| Целостность | 4 из 4 строк `failure_probe`, все таблицы совпали, ограничения совпали, нарушений FK 0 |

Поведение приложения: недоступны только чтения с replica, запись не затронута. Ручных действий не требуется.

## E2. Остановка primary

| Действие | Результат |
|---|---|
| Остановка primary | последняя запись успела попасть на replica |
| Запись на primary | `FAIL`, `Connection refused` |
| Чтение с replica | `OK`, данные на момент остановки |
| Запись на replica | `ERROR: cannot execute INSERT in a read-only transaction` |
| Состояние replica | `in_recovery = t`, walreceiver отсутствует, в primary сама не превращается |
| Лог replica | `could not connect to the primary server`, `waiting for WAL to become available` |
| Запуск primary | replica переподключилась сама, `streaming` через 2,2 с |
| Целостность | 2 новые записи на replica, все таблицы совпали, нарушений FK 0 |

Поведение приложения: запись недоступна до возврата primary или повышения replica; чтение с replica работает, данные устаревают.

## E3. Failover: повышение replica

| Действие | Результат |
|---|---|
| Primary остановлена, запись | `FAIL` |
| `SELECT pg_promote(wait => true)` | `t`, `pg_is_in_recovery = f` |
| Запись на новую primary | `OK`, `id = 39` (последовательность перескочила с 8) |
| Данные | все 7 записей до сбоя на месте, нарушений FK 0 |

## E4. Запуск старой primary после failover

| Действие | Результат |
|---|---|
| Запуск старой primary без изменений | `pg_is_in_recovery = f`, принимает записи |
| Запись на старую primary | `OK`, `id = 8` |
| Сравнение с новой primary | последняя запись разная: `split-brain-old-primary` и `written-on-promoted` (split-brain) |
| Пересборка: `pg_basebackup` с новой primary | `streaming / async`, md5 `orders` совпал, запись `split-brain-old-primary` потеряна |

## Сводка

| Событие | Запись | Чтение | Данные | Ручные действия |
|---|---|---|---|---|
| replica остановлена | работает | с replica нет | без потерь | нет |
| primary остановлена | нет | с replica есть | без потерь | вернуть primary или повысить replica |
| failover | на новой primary | работает | без потерь, id перескакивают | переключить приложение, пересобрать старую primary |
| старая primary запущена без пересборки | пишут обе | расходятся | расхождение | остановить старую, пересобрать |

Автоматического переключения нет: нужно вручную повысить replica и сменить адрес записи в приложении.

## Ограничения

- Репликация асинхронная: при аварийном падении primary последние транзакции, не дошедшие до replica, могут быть потеряны. В тесте остановка штатная (`-m fast`), потерь нет.
- Слота репликации нет: при долгом простое replica может не догнать primary и потребуется пересоздание. Не воспроизводилось.
