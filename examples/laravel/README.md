# Laravel Integration Example

## Installation

```bash
composer require scrywatch/laravel
```

This automatically installs `scrywatch/php` as a dependency.

## Configuration

Publish the config:
```bash
php artisan vendor:publish --tag=scrywatch-config
```

Add to `.env`:
```
SCRYWATCH_API_KEY=your_api_key_here
SCRYWATCH_ENDPOINT=https://api.scrywatch.com
SCRYWATCH_SERVICE=my-laravel-app
SCRYWATCH_ENV=production
```

## Add the logging channel

In `config/logging.php` under `channels`:
```php
'scrywatch' => [
    'driver' => 'custom',
    'via'    => \ScryWatch\Laravel\ScryWatchChannel::class,
],
```

Optionally add to a stack:
```php
'stack' => [
    'driver'   => 'stack',
    'channels' => ['daily', 'scrywatch'],
],
```

## Usage

```php
use Illuminate\Support\Facades\Log;

// Via logging channel
Log::channel('scrywatch')->info('User signed in', ['user_id' => 'u_123']);
Log::channel('scrywatch')->warning('Slow query', ['duration_ms' => 1450]);
Log::channel('scrywatch')->error('Payment failed', ['order_id' => 'ord_456']);

// Cron job (explicit type)
use ScryWatch\ScryWatchClient;
app(ScryWatchClient::class)->log('info', 'cron', 'Daily report complete', ['duration_ms' => 4200]);

// Direct client with user context
$client = app(ScryWatchClient::class);
$client->setUserId(auth()->id());
$client->info('Profile updated');
```

## Monolog level mapping

| Laravel/Monolog level | ScryWatch level |
|-----------------------|----------------|
| DEBUG | `debug` |
| INFO, NOTICE | `info` |
| WARNING | `warn` |
| ERROR, CRITICAL, ALERT, EMERGENCY | `error` |
