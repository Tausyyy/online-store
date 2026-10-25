# Резервное копирование и восстановление PostgreSQL

## Назначение

Скрипт `backup_restore.sh` создаёт резервную копию базы
`online_store`, восстанавливает её в отдельную базу
`online_store_restore` и сравнивает результаты.

Исходная база не изменяется. База восстановления пересоздаётся
при каждом запуске скрипта.

## Требования

- Docker и Docker Compose;
- запущенный сервис PostgreSQL из `compose.yaml`;
- доступ к базе от пользователя `postgres`.

## Запуск

Из корня проекта:

```bash
docker compose up -d db
chmod +x backups/backup_restore.sh
./backups/backup_restore.sh