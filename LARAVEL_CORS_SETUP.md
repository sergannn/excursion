# Настройка CORS для Laravel API

## Проблема
Запросы с `http://localhost:56624` (и других источников) блокируются из-за политики CORS.

## Решение

### Вариант 1: Настройка через config/cors.php (рекомендуется)

Если у вас Laravel 7+ с пакетом `fruitcake/laravel-cors`, настройте файл `config/cors.php`:

```php
<?php

return [
    /*
    |--------------------------------------------------------------------------
    | Cross-Origin Resource Sharing (CORS) Configuration
    |--------------------------------------------------------------------------
    */

    'paths' => ['api/*', 'sanctum/csrf-cookie', 'up'],

    'allowed_methods' => ['*'],

    'allowed_origins' => ['*'],  // Разрешить все источники

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 0,

    'supports_credentials' => false,
];
```

**Важно:** Убедитесь, что путь `'up'` добавлен в массив `paths`, так как именно этот endpoint используется для проверки соединения.

### Вариант 2: Создание собственного CORS middleware

Если пакет `fruitcake/laravel-cors` не установлен, создайте middleware:

1. Создайте middleware:
```bash
php artisan make:middleware Cors
```

2. В файле `app/Http/Middleware/Cors.php`:

```php
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class Cors
{
    public function handle(Request $request, Closure $next)
    {
        $response = $next($request);

        $response->headers->set('Access-Control-Allow-Origin', '*');
        $response->headers->set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
        $response->headers->set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept');

        return $response;
    }
}
```

3. Зарегистрируйте middleware в `app/Http/Kernel.php`:

```php
protected $middleware = [
    // ... другие middleware
    \App\Http\Middleware\Cors::class,
];
```

### Вариант 3: Настройка на уровне веб-сервера (Nginx/Apache)

#### Для Nginx:

Добавьте в конфигурацию вашего сайта:

```nginx
location / {
    add_header 'Access-Control-Allow-Origin' '*' always;
    add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
    add_header 'Access-Control-Allow-Headers' 'Content-Type, Authorization, X-Requested-With, Accept' always;

    if ($request_method = 'OPTIONS') {
        return 204;
    }

    try_files $uri $uri/ /index.php?$query_string;
}
```

#### Для Apache:

Добавьте в `.htaccess` или конфигурацию виртуального хоста:

```apache
<IfModule mod_headers.c>
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
    Header set Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With, Accept"
</IfModule>
```

## Проверка

После настройки проверьте, что заголовки CORS возвращаются:

```bash
curl -I -X OPTIONS https://excursion.panfilius.ru/up \
  -H "Origin: http://localhost:56624" \
  -H "Access-Control-Request-Method: GET"
```

Должны быть заголовки:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: ...`
- `Access-Control-Allow-Headers: ...`

## Безопасность

⚠️ **Важно:** Разрешение всех источников (`*`) подходит для разработки, но для продакшена рекомендуется указать конкретные домены:

```php
'allowed_origins' => [
    'http://localhost:56624',
    'https://your-production-domain.com',
],
```

## После изменений

1. Очистите кэш конфигурации Laravel:
```bash
php artisan config:clear
php artisan cache:clear
```

2. Перезапустите веб-сервер (если использовали настройку на уровне сервера)
