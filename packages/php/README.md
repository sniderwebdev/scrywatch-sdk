# scrywatch/php

Lightweight PHP client for [ScryWatch](https://scrywatch.com) structured log ingest.

## Requirements

- PHP 8.1+
- `curl` extension (only if not providing a PSR-18 HTTP client)

## Installation

```bash
composer require scrywatch/php
```

To use your own HTTP client (Guzzle, Symfony HttpClient, etc.) also require a PSR-18-compatible package:

```bash
composer require guzzlehttp/guzzle
```

## Quickstart

```php
use ScryWatch\ScryWatchClient;

$client = new ScryWatchClient(
    endpoint:    'https://api.scrywatch.com',
    apiKey:      getenv('SCRYWATCH_API_KEY'),
    service:     'api',
    environment: 'production',
);

$client->info('User signed in', ['user_id' => 'u_123']);
$client->warn('Slow query', ['duration_ms' => 1450]);
$client->error('Payment failed', ['order_id' => 'ord_456', 'reason' => 'insufficient_funds']);
```

## With a PSR-18 HTTP client

```php
use GuzzleHttp\Client as GuzzleClient;
use GuzzleHttp\Psr7\HttpFactory;
use ScryWatch\ScryWatchClient;

$factory = new HttpFactory();
$client  = new ScryWatchClient(
    endpoint:       'https://api.scrywatch.com',
    apiKey:         getenv('SCRYWATCH_API_KEY'),
    httpClient:     new GuzzleClient(),
    requestFactory: $factory,
    streamFactory:  $factory,
);
```

## API

| Method | Description |
|--------|-------------|
| `info(message, metadata?)` | Send an info-level log |
| `warn(message, metadata?)` | Send a warn-level log |
| `error(message, metadata?)` | Send an error-level log |
| `debug(message, metadata?)` | Send a debug-level log |
| `log(level, type, message, metadata?)` | Send with explicit level and type |
| `send(events[])` | Send a batch of `LogEvent` objects or raw arrays |
| `setUserId(id)` | Attach a user ID to all subsequent events |

### Valid event types

`crash` `session` `navigation` `api_call` `custom` `cron`

> **Note:** `cron` is accepted by the ScryWatch backend but not yet exposed in the JS or Flutter SDKs.

## Retry behaviour

Retries up to `maxRetries` times (default 3) on network errors or 5xx responses.
Backoff: 500 ms × attempt number (500 ms, 1000 ms, 1500 ms).
4xx responses throw `ScryWatchException` immediately — no retry.
