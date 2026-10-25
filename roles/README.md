# Лабораторная работа № 4 — Роли и права доступа PostgreSQL

## Цель работы

Создать роли администратора, приложения и аналитика, настроить их права доступа и проверить разрешённые и запрещённые операции.

## Роли

| Роль | Права |
|---|---|
| `lab4_admin` | Полные права на существующие таблицы |
| `lab4_app` | Чтение, добавление, изменение и удаление данных |
| `lab4_analyst` | Только чтение данных |

Все три роли имеют атрибут `NOSUPERUSER`, `NOCREATEDB` и `NOCREATEROLE`.

## Файлы

- `sql/roles.sql` — создание ролей и выдача прав.
- `sql/permissions_test.sql` — проверка атрибутов ролей и разрешений.
- `run.sh` — запуск проверок Lab 4.

## Подготовка базы данных

Команды ниже рассчитаны на Linux/WSL с установленным PostgreSQL и доступом через `sudo -u postgres`.

Создайте базу данных:

```bash
sudo -u postgres createdb online_store_lab4
```

Если база уже существует, создавать её повторно не нужно.

Загрузите схему и данные проекта. Из корня репозитория выполните:

```bash
cp migrations/create_tables.sql.sql /tmp/lab4_create_tables.sql
cp data/data.sql /tmp/lab4_data.sql

cd /tmp
sudo -u postgres psql -d online_store_lab4 \
  -v ON_ERROR_STOP=1 -f /tmp/lab4_create_tables.sql

sudo -u postgres psql -d online_store_lab4 \
  -v ON_ERROR_STOP=1 -f /tmp/lab4_data.sql
```

Эти команды предназначены для первоначального заполнения пустой базы. Не запускайте их повторно поверх уже созданных таблиц.

## Создание ролей

Из корня репозитория:

```bash
cp lab4/sql/roles.sql /tmp/lab4_roles.sql
cd /tmp

sudo -u postgres psql -d online_store_lab4 \
  -v ON_ERROR_STOP=1 -f /tmp/lab4_roles.sql
```

Скрипт создания ролей рассчитан на первое применение. При повторном запуске PostgreSQL сообщит, если роли уже существуют.

## Запуск проверок

Из корня репозитория:

```bash
./lab4/run.sh
```

Скрипт проверяет атрибуты ролей и права на таблицу `orders`.

## Практическая демонстрация

Проверка чтения аналитиком:

```bash
cd /tmp
sudo -u postgres psql -d online_store_lab4 \
  -c 'SET ROLE lab4_analyst; SELECT COUNT(*) FROM public.orders;'
```

Ожидается успешный `SELECT`.

Проверка запрета изменения данных аналитиком:

```bash
sudo -u postgres psql -d online_store_lab4 \
  -c 'SET ROLE lab4_analyst; UPDATE public.orders SET status = status WHERE order_id = (SELECT MIN(order_id) FROM public.orders);'
```

Ожидается ошибка `permission denied for table orders`.

Проверка запрета создания ролей приложением:

```bash
sudo -u postgres psql -d online_store_lab4 \
  -c 'SET ROLE lab4_app; CREATE ROLE lab4_test_role;'
```

Ожидается ошибка `permission denied to create role`.

## Ожидаемый результат

- Все три роли не являются суперпользователями.
- `lab4_app` имеет права `SELECT`, `INSERT`, `UPDATE`, `DELETE` на существующие таблицы.
- `lab4_analyst` может читать данные, но не может изменять их.
- Приложение не может создавать новые роли.

