# ScryWatch PHP

Quick guide for integrating ScryWatch into PHP applications.

## Standalone PHP

```bash
composer require scrywatch/php
```

```php
use ScryWatch\ScryWatchClient;

$client = new ScryWatchClient(
    endpoint:    'https://api.scrywatch.com',
    apiKey:      getenv('SCRYWATCH_API_KEY'),
    service:     'my-app',
    environment: 'production',
);

$client->setUserId('user-123');
$client->info('User signed in');
$client->error('Payment failed', ['order_id' => 'ord_789']);
```

See [`/packages/php/README.md`](/packages/php/README.md) for full API reference.

## Laravel

```bash
composer require scrywatch/laravel scrywatch/php
php artisan vendor:publish --tag=scrywatch-config
```

Add to `.env`:
```
SCRYWATCH_API_KEY=your-key
SCRYWATCH_SERVICE=my-app
SCRYWATCH_ENV=production
```

See [`/packages/laravel/README.md`](/packages/laravel/README.md) for full Laravel integration guide.
