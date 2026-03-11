# scrywatch/laravel

Laravel integration for the [ScryWatch PHP client](../php). Provides a ServiceProvider and Monolog channel driver.

## Requirements

- PHP 8.1+
- Laravel 10, 11, or 12
- `scrywatch/php` (installed automatically via Composer)

## Installation

```bash
composer require scrywatch/laravel
```

## Configuration

Publish the config file:
```bash
php artisan vendor:publish --tag=scrywatch-config
```

Add to your `.env`:
```
SCRYWATCH_API_KEY=your_api_key_here
SCRYWATCH_ENDPOINT=https://api.scrywatch.com
SCRYWATCH_SERVICE=my-app
SCRYWATCH_ENV=production
```

## Logging channel

Add to `config/logging.php` under `channels`:
```php
'scrywatch' => [
    'driver' => 'custom',
    'via'    => \ScryWatch\Laravel\ScryWatchChannel::class,
],
```

## Usage

### Via Laravel Log facade

```php
use Illuminate\Support\Facades\Log;

Log::channel('scrywatch')->info('User signed in', ['user_id' => 'u_123']);
Log::channel('scrywatch')->warning('Slow query', ['duration_ms' => 1450]);
Log::channel('scrywatch')->error('Payment failed', ['order_id' => 'ord_456']);
```

### Via ScryWatchClient directly

```php
use ScryWatch\ScryWatchClient;

$client = app(ScryWatchClient::class);
$client->setUserId('user-123');
$client->info('Application event', ['detail' => 'value']);
```

### Add to stack channel

```php
'stack' => [
    'driver'   => 'stack',
    'channels' => ['single', 'scrywatch'],
],
```

## Monolog level mapping

| Monolog level | ScryWatch level |
|---------------|----------------|
| DEBUG | `debug` |
| INFO, NOTICE | `info` |
| WARNING | `warn` |
| ERROR, CRITICAL, ALERT, EMERGENCY | `error` |
