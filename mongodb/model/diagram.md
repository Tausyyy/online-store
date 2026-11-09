# Диаграмма модели MongoDB

```mermaid
erDiagram
    PG_PRODUCTS ||--o| product_content : "productId"
    PG_PRODUCTS ||--o{ product_reviews : "productId"
    PG_PRODUCTS ||--o{ product_questions : "productId"
    PG_CUSTOMERS ||--o{ product_reviews : "customerId"
    PG_CUSTOMERS ||--o{ product_questions : "customerId"
    product_showcases }o--o{ product_content : "productIds"

    PG_PRODUCTS {
        BIGINT product_id PK
    }
    PG_CUSTOMERS {
        BIGINT customer_id PK
    }
    product_content {
        ObjectId _id PK
        String productId UK
        String title
        String description
        Object attributes "embedded"
        Array tags "embedded"
        Array gallery "embedded: url, alt"
        Int32 schemaVersion
        Date createdAt
        Date updatedAt
    }
    product_reviews {
        ObjectId _id PK
        String productId FK
        String customerId FK
        Int32 rating
        String text
        String status
        Int32 schemaVersion
        Date createdAt
        Date updatedAt
    }
    product_questions {
        ObjectId _id PK
        String productId FK
        String customerId FK
        String question
        String answer
        String status
        Int32 schemaVersion
        Date createdAt
        Date updatedAt
    }
    product_showcases {
        ObjectId _id PK
        String name
        String slug UK
        String description
        Array productIds "references"
        String status
        Int32 schemaVersion
        Date createdAt
        Date updatedAt
    }
```

## Описание модели

| Связь | Тип | Реализация |
|---|---|---|
| `product_content` → `product_reviews` | 1:N | reference: `product_reviews.productId` |
| `product_content` → `product_questions` | 1:N | reference: `product_questions.productId` |
| `product_showcases` ↔ `product_content` | M:N | массив reference `product_showcases.productIds` |
| `customers` ↔ товары через отзывы | M:N | `product_reviews` с уникальным индексом `{ productId, customerId }` |
| `product_content` → `attributes`, `tags`, `gallery` | 1:1 | embedding внутри документа товара |
| `product_questions` → `answer` | 1:1 | embedding внутри документа вопроса |

`PG_PRODUCTS` и `PG_CUSTOMERS` — таблицы PostgreSQL `products` и `customers`. Ссылки на них хранятся строками с десятичным значением `BIGINT`, внешних ключей между СУБД нет.
