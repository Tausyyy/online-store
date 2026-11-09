# MongoDB: проектирование коллекций

## Состав

| Файл | Назначение |
|---|---|
| `collections.js` | Создание коллекции `product_showcases`, настройка валидации и индексов, повторное использование коллекций из `../operations/validation.js` |
| `demo.js` | Пример документов, запросы по связям 1:N, M:N и embedding, отклонённые операции |
| `benchmark.js` | Сравнение embedding и reference на двух нагрузках |
| `diagram.md` | Диаграмма модели |
| `embedding_reference.md` | Обоснование embedding и reference |
| `package.json` | Скрипты и зависимость `mongodb` |

## Запуск

Из корня репозитория:

```bash
docker compose -f mongodb/operations/docker-compose.yml up -d

cd mongodb/operations
npm install
cd ../model
npm install

npm run check
npm run model
npm run demo
mkdir -p results
npm run benchmark | tee results/benchmark.txt
```

По умолчанию используются `mongodb://127.0.0.1:27017` и база `online_store`. Переопределяются переменными `MONGODB_URI` и `MONGODB_DB`. Замер использует отдельную базу `online_store_bench` (`MONGODB_BENCH_DB`).

## Совместимость с mongodb/operations

- Имена и поля `product_content`, `product_reviews`, `product_questions` не изменяются, схема берётся из `../operations/validation.js`.
- Идентификаторы PostgreSQL хранятся строками с положительным десятичным числом.
- Во всех документах есть `schemaVersion: 1`, `createdAt`, `updatedAt`.
- Валидация везде `strict` + `error`.
- Демонстрационные данные используют `productId` от `900001` и удаляются в конце `demo.js`.
