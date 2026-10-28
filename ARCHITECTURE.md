# Архитектура проекта

```mermaid
flowchart TD
    A[Flutter UI\n(lib/src/features/...)] -->|использует| B[Riverpod провайдеры\nlib/src/data/providers.dart]
    B -->|создают| C[Репозитории\nlib/src/data/repositories/*]
    C -->|через| D[ApiClient\nlib/src/core/api/api_client.dart]
    D -->|HTTP запросы| E[Laravel API\nhttps://excursion.panfilius.ru]
    E -->|возвращает JSON| C
    C -->|модели| F[Data Models\nlib/src/data/models/*]
    B -->|Auth state| G[authController\nfeatures/auth]
    G -->|визуализация| H[AppShell + экраны ролей]
    H -->|авторизация| A
```
