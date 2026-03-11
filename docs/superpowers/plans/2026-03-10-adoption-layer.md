# ScryWatch Adoption Layer — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add PHP, Go, Laravel, and Go HTTP middleware packages; HTTP/PHP/Go/Laravel examples; OTel collector configs; Kubernetes deployment assets; and developer docs to make ScryWatch adoptable from multiple stacks.

**Architecture:** Four installable packages under `/packages/` (PHP PSR-18 client, Go stdlib client, Laravel ServiceProvider wrapping PHP, Go net/http middleware importing sdk-go). Config/doc assets in `/examples/`, `/otel/`, `/kubernetes/`, `/docs/` at repo root. Existing `/js` and `/flutter` untouched.

**Tech Stack:** PHP 8.1+, Composer, PSR-18/17 interfaces, PHPUnit, nyholm/psr7 (test-only); Go 1.21+, stdlib only for sdk-go, sdk-go as dep for sdk-go-http; Laravel 10-12, Monolog 3; OTel Collector YAML; Kubernetes YAML + Helm values.

**Spec:** `docs/superpowers/specs/2026-03-10-scrywatch-adoption-layer-design.md`

---

## Chunk 1: PHP Package (`packages/php`)

### File Map

| File | Purpose |
|------|---------|
| `packages/php/composer.json` | Package manifest, PSR-4 autoload, deps |
| `packages/php/src/LogEvent.php` | Immutable value object — one event |
| `packages/php/src/ScryWatchException.php` | Single exception class for all errors |
| `packages/php/src/Http/CurlHttpClient.php` | Internal curl fallback (no PSR-7 dep) |
| `packages/php/src/ScryWatchClient.php` | Main client: PSR-18 path + curl fallback |
| `packages/php/tests/LogEventTest.php` | Unit tests for LogEvent serialisation |
| `packages/php/tests/ScryWatchClientTest.php` | Behaviour tests via mocked PSR-18 |
| `packages/php/README.md` | Quickstart and API reference |
| `packages/php/.gitignore` | Ignore vendor/ |

---

### Task 1.1 — Scaffold composer.json

**Files:** Create `packages/php/composer.json`, `packages/php/.gitignore`

- [ ] **Create `packages/php/composer.json`:**

```json
{
  "name": "scrywatch/php",
  "description": "Lightweight PHP client for ScryWatch structured log ingest",
  "type": "library",
  "license": "MIT",
  "require": {
    "php": "^8.1",
    "psr/http-client": "^1.0",
    "psr/http-factory": "^1.0"
  },
  "require-dev": {
    "phpunit/phpunit": "^10.0",
    "nyholm/psr7": "^1.8"
  },
  "autoload": {
    "psr-4": {
      "ScryWatch\\": "src/"
    }
  },
  "autoload-dev": {
    "psr-4": {
      "ScryWatch\\Tests\\": "tests/"
    }
  },
  "config": {
    "optimize-autoloader": true
  }
}
```

- [ ] **Create `packages/php/.gitignore`:**

```
/vendor/
/composer.lock
```

- [ ] **Install dependencies:**

```bash
cd packages/php && composer install
```

Expected: `vendor/` created, no errors.

- [ ] **Commit:**

```bash
git add packages/php/composer.json packages/php/.gitignore
git commit -m "feat(php): scaffold composer package"
```

---

### Task 1.2 — LogEvent value object

**Files:** Create `packages/php/src/LogEvent.php`, `packages/php/tests/LogEventTest.php`

- [ ] **Write the failing test** — `packages/php/tests/LogEventTest.php`:

```php
<?php
declare(strict_types=1);

namespace ScryWatch\Tests;

use PHPUnit\Framework\TestCase;
use ScryWatch\LogEvent;

class LogEventTest extends TestCase
{
    public function test_toArray_includes_required_fields(): void
    {
        $event = new LogEvent(
            level: 'error',
            type: 'custom',
            message: 'Something broke',
            timestamp: 1741200000000,
        );

        $data = $event->toArray();

        $this->assertSame('error', $data['level']);
        $this->assertSame('custom', $data['type']);
        $this->assertSame('Something broke', $data['message']);
        $this->assertSame(1741200000000, $data['timestamp']);
    }

    public function test_toArray_omits_null_optional_fields(): void
    {
        $event = new LogEvent(level: 'info', type: 'custom', message: 'hi', timestamp: 1000);
        $data  = $event->toArray();

        $this->assertArrayNotHasKey('user_id', $data);
        $this->assertArrayNotHasKey('session_id', $data);
        $this->assertArrayNotHasKey('environment', $data);
        $this->assertArrayNotHasKey('service', $data);
        $this->assertArrayNotHasKey('device_type', $data);
        $this->assertArrayNotHasKey('trace_id', $data);
        $this->assertArrayNotHasKey('span_id', $data);
        $this->assertArrayNotHasKey('metadata', $data);
    }

    public function test_toArray_includes_optional_fields_when_set(): void
    {
        $event = new LogEvent(
            level: 'warn',
            type: 'api_call',
            message: 'slow request',
            timestamp: 2000,
            userId: 'u1',
            sessionId: 's1',
            environment: 'production',
            service: 'api',
            deviceType: 'desktop',
            traceId: 'abc',
            spanId: 'def',
            metadata: ['latency_ms' => 1200],
        );

        $data = $event->toArray();

        $this->assertSame('u1', $data['user_id']);
        $this->assertSame('s1', $data['session_id']);
        $this->assertSame('production', $data['environment']);
        $this->assertSame('api', $data['service']);
        $this->assertSame('desktop', $data['device_type']);
        $this->assertSame('abc', $data['trace_id']);
        $this->assertSame('def', $data['span_id']);
        $this->assertSame(['latency_ms' => 1200], $data['metadata']);
    }
}
```

- [ ] **Run test — expect failure:**

```bash
cd packages/php && ./vendor/bin/phpunit tests/LogEventTest.php
```

Expected: `Error: Class "ScryWatch\LogEvent" not found`

- [ ] **Implement `packages/php/src/LogEvent.php`:**

```php
<?php
declare(strict_types=1);

namespace ScryWatch;

final class LogEvent
{
    public function __construct(
        public readonly string  $level,
        public readonly string  $type,
        public readonly string  $message,
        public readonly int     $timestamp,
        public readonly ?string $userId      = null,
        public readonly ?string $sessionId   = null,
        public readonly ?string $environment = null,
        public readonly ?string $service     = null,
        public readonly ?string $deviceType  = null,
        public readonly ?string $traceId     = null,
        public readonly ?string $spanId      = null,
        public readonly ?array  $metadata    = null,
    ) {}

    public function toArray(): array
    {
        $data = [
            'level'     => $this->level,
            'type'      => $this->type,
            'message'   => $this->message,
            'timestamp' => $this->timestamp,
        ];

        if ($this->userId      !== null) $data['user_id']     = $this->userId;
        if ($this->sessionId   !== null) $data['session_id']  = $this->sessionId;
        if ($this->environment !== null) $data['environment'] = $this->environment;
        if ($this->service     !== null) $data['service']     = $this->service;
        if ($this->deviceType  !== null) $data['device_type'] = $this->deviceType;
        if ($this->traceId     !== null) $data['trace_id']    = $this->traceId;
        if ($this->spanId      !== null) $data['span_id']     = $this->spanId;
        if ($this->metadata    !== null) $data['metadata']    = $this->metadata;

        return $data;
    }
}
```

- [ ] **Run test — expect pass:**

```bash
cd packages/php && ./vendor/bin/phpunit tests/LogEventTest.php
```

Expected: `OK (3 tests, 14 assertions)`

- [ ] **Commit:**

```bash
git add packages/php/src/LogEvent.php packages/php/tests/LogEventTest.php
git commit -m "feat(php): add LogEvent value object"
```

---

### Task 1.3 — Exception and internal curl client

**Files:** Create `packages/php/src/ScryWatchException.php`, `packages/php/src/Http/CurlHttpClient.php`

> **TDD note:** `ScryWatchException` is a trivial subclass with no logic; no unit test is required.
> `CurlHttpClient` wraps the `curl` C extension and cannot be unit-tested without a live HTTP server
> or extension mocking. Its behaviour is exercised by integration tests (run `./vendor/bin/phpunit`
> with a real endpoint). The PSR-18 path — which is the tested path — exercises the same retry and
> envelope logic in `ScryWatchClient`.

- [ ] **Create `packages/php/src/ScryWatchException.php`:**

```php
<?php
declare(strict_types=1);

namespace ScryWatch;

class ScryWatchException extends \RuntimeException {}
```

- [ ] **Create `packages/php/src/Http/CurlHttpClient.php`:**

```php
<?php
declare(strict_types=1);

namespace ScryWatch\Http;

use ScryWatch\ScryWatchException;

/**
 * Internal HTTP client backed by the curl extension.
 * Not PSR-18 compliant — used only when no PSR-18 client is injected.
 *
 * Returns 0 on transport failure (curl_exec === false) so that
 * ScryWatchClient::sendWithRetry() can apply its retry logic uniformly.
 * Only throws ScryWatchException when the curl extension is missing entirely.
 */
final class CurlHttpClient
{
    /**
     * @param string   $url
     * @param string[] $headers  Formatted as "Header-Name: value"
     * @param string   $body     Raw request body
     * @param int      $timeout  Seconds
     *
     * @return int HTTP status code, or 0 on transport failure
     * @throws ScryWatchException if the curl extension is not loaded
     */
    public function post(string $url, array $headers, string $body, int $timeout = 5): int
    {
        if (!extension_loaded('curl')) {
            throw new ScryWatchException(
                'The curl PHP extension is required when no PSR-18 HTTP client is provided.'
            );
        }

        $ch = curl_init($url);

        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
        ]);

        $result   = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        // Return 0 on transport failure; sendWithRetry treats 0 as a retriable error.
        if ($result === false) {
            return 0;
        }

        return (int) $httpCode;
    }
}
```

- [ ] **Commit:**

```bash
git add packages/php/src/ScryWatchException.php packages/php/src/Http/CurlHttpClient.php
git commit -m "feat(php): add ScryWatchException and CurlHttpClient"
```

---

### Task 1.4 — ScryWatchClient

**Files:** Create `packages/php/src/ScryWatchClient.php`, `packages/php/tests/ScryWatchClientTest.php`

- [ ] **Write the failing tests** — `packages/php/tests/ScryWatchClientTest.php`:

```php
<?php
declare(strict_types=1);

namespace ScryWatch\Tests;

use Nyholm\Psr7\Factory\Psr17Factory;
use Nyholm\Psr7\Response;
use PHPUnit\Framework\TestCase;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestInterface;
use ScryWatch\ScryWatchClient;
use ScryWatch\ScryWatchException;

class ScryWatchClientTest extends TestCase
{
    private Psr17Factory $factory;

    protected function setUp(): void
    {
        $this->factory = new Psr17Factory();
    }

    private function makeClient(int $statusCode = 202, ?callable $assert = null): ScryWatchClient
    {
        $httpClient = $this->createMock(ClientInterface::class);
        $response   = new Response($statusCode);

        $expectation = $httpClient->expects($this->atLeastOnce())
            ->method('sendRequest');

        if ($assert !== null) {
            $expectation->with($this->callback($assert));
        }

        $expectation->willReturn($response);

        return new ScryWatchClient(
            endpoint:       'https://api.example.com',
            apiKey:         'test-key',
            maxRetries:     0,
            httpClient:     $httpClient,
            requestFactory: $this->factory,
            streamFactory:  $this->factory,
        );
    }

    public function test_info_sends_without_error(): void
    {
        $client = $this->makeClient(202);
        $client->info('Hello world');
        $this->assertTrue(true); // no exception = pass
    }

    public function test_request_uses_correct_endpoint_and_auth(): void
    {
        $client = $this->makeClient(202, function (RequestInterface $req): bool {
            $this->assertSame('POST', $req->getMethod());
            $this->assertStringEndsWith('/api/ingest', (string) $req->getUri());
            $this->assertSame('Bearer test-key', $req->getHeaderLine('Authorization'));
            $this->assertSame('application/json', $req->getHeaderLine('Content-Type'));
            return true;
        });

        $client->info('test');
    }

    public function test_request_body_has_events_envelope(): void
    {
        $client = $this->makeClient(202, function (RequestInterface $req): bool {
            $body = json_decode((string) $req->getBody(), true);
            $this->assertArrayHasKey('events', $body);
            $this->assertCount(1, $body['events']);
            $this->assertSame('info', $body['events'][0]['level']);
            $this->assertSame('custom', $body['events'][0]['type']);
            $this->assertSame('envelope test', $body['events'][0]['message']);
            return true;
        });

        $client->info('envelope test');
    }

    public function test_4xx_throws_immediately_without_retry(): void
    {
        $httpClient = $this->createMock(ClientInterface::class);
        $httpClient->expects($this->once()) // exactly once — no retry
            ->method('sendRequest')
            ->willReturn(new Response(400));

        $client = new ScryWatchClient(
            endpoint:       'https://api.example.com',
            apiKey:         'key',
            maxRetries:     3,
            httpClient:     $httpClient,
            requestFactory: $this->factory,
            streamFactory:  $this->factory,
        );

        $this->expectException(ScryWatchException::class);
        $client->info('bad event');
    }

    public function test_5xx_retries_up_to_max_retries(): void
    {
        $httpClient = $this->createMock(ClientInterface::class);
        $httpClient->expects($this->exactly(3)) // initial + 2 retries
            ->method('sendRequest')
            ->willReturn(new Response(503));

        $client = new ScryWatchClient(
            endpoint:       'https://api.example.com',
            apiKey:         'key',
            maxRetries:     2,
            httpClient:     $httpClient,
            requestFactory: $this->factory,
            streamFactory:  $this->factory,
        );

        $this->expectException(ScryWatchException::class);
        $client->info('server error');
    }

    public function test_setUserId_attaches_to_events(): void
    {
        $client = $this->makeClient(202, function (RequestInterface $req): bool {
            $body = json_decode((string) $req->getBody(), true);
            $this->assertSame('user-42', $body['events'][0]['user_id']);
            return true;
        });

        $client->setUserId('user-42');
        $client->info('with user');
    }

    public function test_warn_error_debug_use_correct_levels(): void
    {
        foreach (['warn', 'error', 'debug'] as $level) {
            $client = $this->makeClient(202, function (RequestInterface $req) use ($level): bool {
                $body = json_decode((string) $req->getBody(), true);
                $this->assertSame($level, $body['events'][0]['level']);
                return true;
            });
            $client->$level("{$level} message");
        }
    }
}
```

- [ ] **Run test — expect failure:**

```bash
cd packages/php && ./vendor/bin/phpunit tests/ScryWatchClientTest.php
```

Expected: `Error: Class "ScryWatch\ScryWatchClient" not found`

- [ ] **Implement `packages/php/src/ScryWatchClient.php`:**

```php
<?php
declare(strict_types=1);

namespace ScryWatch;

use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Psr\Http\Message\StreamFactoryInterface;
use ScryWatch\Http\CurlHttpClient;

class ScryWatchClient
{
    private ?string $userId = null;
    private readonly CurlHttpClient $curlClient;

    public function __construct(
        private readonly string                    $endpoint,
        private readonly string                    $apiKey,
        private readonly ?string                   $service        = null,
        private readonly ?string                   $environment    = null,
        private readonly int                       $maxRetries     = 3,
        private readonly ?ClientInterface          $httpClient     = null,
        private readonly ?RequestFactoryInterface  $requestFactory = null,
        private readonly ?StreamFactoryInterface   $streamFactory  = null,
    ) {
        $this->curlClient = new CurlHttpClient();
    }

    public function setUserId(string $id): void
    {
        $this->userId = $id;
    }

    public function info(string $message, array $metadata = []): void
    {
        $this->log('info', 'custom', $message, $metadata);
    }

    public function warn(string $message, array $metadata = []): void
    {
        $this->log('warn', 'custom', $message, $metadata);
    }

    public function error(string $message, array $metadata = []): void
    {
        $this->log('error', 'custom', $message, $metadata);
    }

    public function debug(string $message, array $metadata = []): void
    {
        $this->log('debug', 'custom', $message, $metadata);
    }

    public function log(string $level, string $type, string $message, array $metadata = []): void
    {
        $event = new LogEvent(
            level:       $level,
            type:        $type,
            message:     $message,
            timestamp:   (int) (microtime(true) * 1000),
            userId:      $this->userId,
            environment: $this->environment,
            service:     $this->service,
            metadata:    $metadata ?: null,
        );

        $this->send([$event]);
    }

    /**
     * @param array<LogEvent|array<string,mixed>> $events
     */
    public function send(array $events): void
    {
        $payload = json_encode([
            'events' => array_map(
                static fn($e) => $e instanceof LogEvent ? $e->toArray() : $e,
                $events
            ),
        ], JSON_THROW_ON_ERROR);

        $url     = rtrim($this->endpoint, '/') . '/api/ingest';
        $headers = [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $this->apiKey,
        ];

        $this->sendWithRetry($url, $headers, $payload);
    }

    private function sendWithRetry(string $url, array $headers, string $body): void
    {
        $lastException = null;

        for ($attempt = 0; $attempt <= $this->maxRetries; $attempt++) {
            if ($attempt > 0) {
                usleep($attempt * 500_000);
            }

            try {
                $status = $this->doRequest($url, $headers, $body);
            } catch (\Throwable $e) {
                // PSR-18 ClientException or similar transport error — retriable.
                $lastException = new ScryWatchException(
                    "ScryWatch ingest request failed: {$e->getMessage()}",
                    0,
                    $e
                );
                continue;
            }

            // Only HTTP 202 is the defined success code per the ScryWatch API contract.
            if ($status === 202) {
                return;
            }

            // 4xx = client error; throw immediately without retrying.
            if ($status >= 400 && $status < 500) {
                throw new ScryWatchException(
                    "ScryWatch ingest rejected the request with HTTP {$status}."
                );
            }

            // 0 = transport failure from CurlHttpClient (curl_exec returned false).
            // 5xx = server error. Both are retriable.
            $errorMsg = $status === 0
                ? 'ScryWatch ingest transport failure (curl error).'
                : "ScryWatch ingest returned HTTP {$status}.";

            $lastException = new ScryWatchException($errorMsg);
        }

        throw $lastException ?? new ScryWatchException('ScryWatch ingest failed after retries.');
    }

    private function doRequest(string $url, array $headers, string $body): int
    {
        if ($this->httpClient !== null
            && $this->requestFactory !== null
            && $this->streamFactory !== null
        ) {
            $stream  = $this->streamFactory->createStream($body);
            $request = $this->requestFactory->createRequest('POST', $url)
                ->withBody($stream)
                ->withHeader('Content-Type', 'application/json')
                ->withHeader('Authorization', 'Bearer ' . $this->apiKey);

            $response = $this->httpClient->sendRequest($request);
            return $response->getStatusCode();
        }

        return $this->curlClient->post($url, $headers, $body);
    }
}
```

- [ ] **Run tests — expect all pass:**

```bash
cd packages/php && ./vendor/bin/phpunit
```

Expected: `OK (9 tests, N assertions)`

- [ ] **Commit:**

```bash
git add packages/php/src/ScryWatchClient.php packages/php/tests/ScryWatchClientTest.php
git commit -m "feat(php): implement ScryWatchClient with PSR-18 + curl fallback"
```

---

### Task 1.5 — PHP README

**File:** Create `packages/php/README.md`

- [ ] **Create `packages/php/README.md`:**

````markdown
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
````

- [ ] **Commit:**

```bash
git add packages/php/README.md
git commit -m "docs(php): add README with quickstart"
```

---

## Chunk 2: Go Package (`packages/go`)

### File Map

| File | Purpose |
|------|---------|
| `packages/go/go.mod` | Module declaration |
| `packages/go/go.sum` | Generated; empty for zero-dep module, must be committed |
| `packages/go/event.go` | `LogEvent` struct |
| `packages/go/options.go` | Functional options + internal `config` struct |
| `packages/go/client.go` | `Client` — constructor, Send, Info/Warn/Error/Debug, SetUserID |
| `packages/go/client_test.go` | Behaviour tests using `httptest.NewServer` |
| `packages/go/example_test.go` | Runnable example |
| `packages/go/README.md` | Quickstart |

---

### Task 2.1 — Module scaffold and event type

**Files:** Create `packages/go/go.mod`, `packages/go/event.go`

- [ ] **Create `packages/go/go.mod`:**

```
module github.com/scrywatch/sdk-go

go 1.21
```

- [ ] **Create `packages/go/event.go`:**

```go
package scrywatch

// LogEvent is a single structured log event sent to ScryWatch.
//
// Wire format uses snake_case JSON; omitempty fields are omitted when zero-value.
// Valid Levels: error, warn, info, debug.
// Valid Types:  crash, session, navigation, api_call, custom, cron.
// Note: cron is accepted by the backend but not yet in the JS/Flutter SDKs.
type LogEvent struct {
	Level       string         `json:"level"`
	Type        string         `json:"type"`
	Message     string         `json:"message"`
	Timestamp   int64          `json:"timestamp"` // Unix milliseconds
	UserID      string         `json:"user_id,omitempty"`
	SessionID   string         `json:"session_id,omitempty"`
	Environment string         `json:"environment,omitempty"`
	Service     string         `json:"service,omitempty"`
	DeviceType  string         `json:"device_type,omitempty"`
	TraceID     string         `json:"trace_id,omitempty"`
	SpanID      string         `json:"span_id,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty"`
}
```

- [ ] **Run `go mod tidy` to generate go.sum:**

```bash
cd packages/go && go mod tidy
```

Expected: `go.sum` created (empty for zero-dep module).

- [ ] **Commit:**

```bash
git add packages/go/go.mod packages/go/go.sum packages/go/event.go
git commit -m "feat(go): scaffold module and LogEvent type"
```

---

### Task 2.2 — Options

**File:** Create `packages/go/options.go`

> **TDD note:** `options.go` contains only struct field mutations — no branching logic.
> No failing test is written first; all options are validated indirectly through `TestClient_*` tests
> in Task 2.3 (e.g. `WithMaxRetries` is exercised by the retry count test).

- [ ] **Create `packages/go/options.go`:**

```go
package scrywatch

import (
	"net/http"
	"time"
)

type config struct {
	httpClient  *http.Client
	service     string
	environment string
	maxRetries  int
	timeout     time.Duration
}

// Option configures a Client.
type Option func(*config)

// WithHTTPClient sets the HTTP client used for requests.
// Defaults to a client with a 5-second timeout.
func WithHTTPClient(c *http.Client) Option {
	return func(cfg *config) { cfg.httpClient = c }
}

// WithService tags every event with the given service name.
func WithService(s string) Option {
	return func(cfg *config) { cfg.service = s }
}

// WithEnvironment tags every event with the given environment label.
func WithEnvironment(e string) Option {
	return func(cfg *config) { cfg.environment = e }
}

// WithMaxRetries sets how many times to retry on network error or 5xx response.
// Default is 3.
func WithMaxRetries(n int) Option {
	return func(cfg *config) { cfg.maxRetries = n }
}

// WithTimeout sets the per-request HTTP timeout.
// Default is 5 seconds. This option has no effect when a custom
// HTTP client is provided via WithHTTPClient — configure the
// timeout on that client directly instead.
func WithTimeout(d time.Duration) Option {
	return func(cfg *config) { cfg.timeout = d }
}
```

- [ ] **Commit:**

```bash
git add packages/go/options.go
git commit -m "feat(go): add functional options"
```

---

### Task 2.3 — Client with tests

**Files:** Create `packages/go/client.go`, `packages/go/client_test.go`

- [ ] **Write the failing tests** — `packages/go/client_test.go`:

```go
package scrywatch_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	scrywatch "github.com/scrywatch/sdk-go"
)

func newTestServer(t *testing.T, statusCode int, assertFn func(*http.Request)) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if assertFn != nil {
			assertFn(r)
		}
		w.WriteHeader(statusCode)
	}))
}

func TestClient_Info_success(t *testing.T) {
	srv := newTestServer(t, 202, nil)
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "test-key")
	if err := client.Info(context.Background(), "hello", nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestClient_Send_usesEventsEnvelope(t *testing.T) {
	var body map[string]any

	srv := newTestServer(t, 202, func(r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		json.Unmarshal(b, &body) //nolint
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key")
	_ = client.Info(context.Background(), "envelope check", nil)

	if _, ok := body["events"]; !ok {
		t.Fatal("request body missing 'events' key")
	}
	events := body["events"].([]any)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
}

func TestClient_Send_setsAuthHeader(t *testing.T) {
	// assertFn is a closure that captures t; t.Errorf is safe here because
	// httptest handlers run synchronously relative to the client.Do() call.
	srv := newTestServer(t, 202, func(r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer my-api-key" {
			t.Errorf("wrong Authorization header: got %q, want %q", got, "Bearer my-api-key")
		}
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "my-api-key")
	_ = client.Info(context.Background(), "auth test", nil)
}

func TestClient_Send_postsToIngestPath(t *testing.T) {
	srv := newTestServer(t, 202, func(r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/api/ingest") {
			t.Errorf("wrong path: got %q, want suffix /api/ingest", r.URL.Path)
		}
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key")
	_ = client.Info(context.Background(), "path test", nil)
}

func TestClient_Send_4xxFailsImmediately(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(400)
	}))
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key", scrywatch.WithMaxRetries(3))
	err := client.Info(context.Background(), "bad", nil)

	if err == nil {
		t.Fatal("expected error for 4xx, got nil")
	}
	if callCount != 1 {
		t.Fatalf("expected 1 call (no retry on 4xx), got %d", callCount)
	}
}

func TestClient_Send_5xxRetries(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(503)
	}))
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key", scrywatch.WithMaxRetries(2))
	err := client.Info(context.Background(), "retry test", nil)

	if err == nil {
		t.Fatal("expected error after exhausted retries, got nil")
	}
	if callCount != 3 { // initial + 2 retries
		t.Fatalf("expected 3 calls (initial + 2 retries), got %d", callCount)
	}
}

func TestClient_SetUserID_attachesToEvents(t *testing.T) {
	var body map[string]any

	srv := newTestServer(t, 202, func(r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		json.Unmarshal(b, &body) //nolint
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key")
	client.SetUserID("user-99")
	_ = client.Info(context.Background(), "with user", nil)

	events := body["events"].([]any)
	event := events[0].(map[string]any)
	if event["user_id"] != "user-99" {
		t.Fatalf("expected user_id=user-99, got %v", event["user_id"])
	}
}
```

- [ ] **Run test — expect failure (package doesn't exist yet):**

```bash
cd packages/go && go test ./... 2>&1 | head -5
```

Expected: `cannot find package` or `undefined: NewClient`

- [ ] **Implement `packages/go/client.go`:**

```go
package scrywatch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

// Client sends log events to ScryWatch.
// Safe for concurrent use.
type Client struct {
	endpoint    string
	apiKey      string
	httpClient  *http.Client
	service     string
	environment string
	maxRetries  int
	userID      atomic.Value // stores string
}

// NewClient creates a new ScryWatch client.
//
//	client := scrywatch.NewClient("https://api.scrywatch.com", "YOUR_API_KEY",
//	    scrywatch.WithService("api"),
//	    scrywatch.WithEnvironment("production"),
//	)
func NewClient(endpoint, apiKey string, opts ...Option) *Client {
	cfg := &config{
		maxRetries: 3,
		timeout:    5 * time.Second,
	}
	for _, o := range opts {
		o(cfg)
	}
	if cfg.httpClient == nil {
		cfg.httpClient = &http.Client{Timeout: cfg.timeout}
	}
	return &Client{
		endpoint:    endpoint,
		apiKey:      apiKey,
		httpClient:  cfg.httpClient,
		service:     cfg.service,
		environment: cfg.environment,
		maxRetries:  cfg.maxRetries,
	}
}

// SetUserID attaches a user ID to all subsequent log events.
// Safe for concurrent use.
func (c *Client) SetUserID(id string) {
	c.userID.Store(id)
}

func (c *Client) userIDStr() string {
	v := c.userID.Load()
	if v == nil {
		return ""
	}
	return v.(string)
}

// Info sends an info-level custom event.
func (c *Client) Info(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "info", "custom", message, metadata)
}

// Warn sends a warn-level custom event.
func (c *Client) Warn(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "warn", "custom", message, metadata)
}

// Error sends an error-level custom event.
func (c *Client) Error(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "error", "custom", message, metadata)
}

// Debug sends a debug-level custom event.
func (c *Client) Debug(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "debug", "custom", message, metadata)
}

func (c *Client) log(ctx context.Context, level, typ, message string, metadata map[string]any) error {
	event := LogEvent{
		Level:       level,
		Type:        typ,
		Message:     message,
		Timestamp:   time.Now().UnixMilli(),
		UserID:      c.userIDStr(),
		Environment: c.environment,
		Service:     c.service,
		Metadata:    metadata,
	}
	return c.Send(ctx, []LogEvent{event})
}

// Send posts a batch of events to ScryWatch ingest.
// Retries on network errors and 5xx responses (up to MaxRetries).
// 4xx responses return an error immediately without retrying.
func (c *Client) Send(ctx context.Context, events []LogEvent) error {
	payload, err := json.Marshal(map[string]any{"events": events})
	if err != nil {
		return fmt.Errorf("scrywatch: marshal: %w", err)
	}

	url := strings.TrimRight(c.endpoint, "/") + "/api/ingest"

	backoff := 100 * time.Millisecond
	var lastErr error

	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(backoff):
			}
			backoff *= 2
		}

		status, err := c.doRequest(ctx, url, payload)
		if err == nil && status == 202 {
			return nil
		}
		if err == nil && status >= 400 && status < 500 {
			return fmt.Errorf("scrywatch: ingest rejected: HTTP %d", status)
		}
		if err != nil {
			lastErr = fmt.Errorf("scrywatch: request: %w", err)
		} else {
			lastErr = fmt.Errorf("scrywatch: ingest: HTTP %d", status)
		}
	}

	return lastErr
}

func (c *Client) doRequest(ctx context.Context, url string, body []byte) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("do request: %w", err)
	}
	resp.Body.Close()
	return resp.StatusCode, nil
}
```

- [ ] **Run tests — expect all pass:**

```bash
cd packages/go && go test ./... -v -count=1
```

Expected: `PASS` for all test functions.

- [ ] **Commit:**

```bash
git add packages/go/client.go packages/go/client_test.go
git commit -m "feat(go): implement Client with retry and Send"
```

---

### Task 2.4 — Example and README

**Files:** Create `packages/go/example_test.go`, `packages/go/README.md`

- [ ] **Create `packages/go/example_test.go`:**

```go
package scrywatch_test

import (
	"context"

	scrywatch "github.com/scrywatch/sdk-go"
)

func Example() {
	client := scrywatch.NewClient(
		"https://api.scrywatch.com",
		"YOUR_API_KEY",
		scrywatch.WithService("api"),
		scrywatch.WithEnvironment("production"),
	)

	client.SetUserID("user-123")

	_ = client.Info(context.Background(), "User signed in", map[string]any{
		"plan": "pro",
	})

	_ = client.Send(context.Background(), []scrywatch.LogEvent{
		{Level: "warn", Type: "api_call", Message: "slow downstream", Timestamp: 1741200000000,
			Metadata: map[string]any{"duration_ms": 1450}},
	})
}
```

  > **Note:** `Example()` intentionally has no `// Output:` comment. Go's testing framework only runs an Example as a testable example when `// Output:` is present; without it the example is compiled and its signature verified but not executed, which is correct here because `client.Info` would make a real network call.

- [ ] **Verify example compiles:**

```bash
cd packages/go && go build ./...
```

Expected: no output (success).

- [ ] **Create `packages/go/README.md`:**

````markdown
# github.com/scrywatch/sdk-go

Lightweight Go client for [ScryWatch](https://scrywatch.com) structured log ingest. Zero non-stdlib dependencies.

## Requirements

- Go 1.21+

## Installation

```bash
go get github.com/scrywatch/sdk-go
```

## Quickstart

```go
import (
    "context"
    scrywatch "github.com/scrywatch/sdk-go"
)

client := scrywatch.NewClient(
    "https://api.scrywatch.com",
    os.Getenv("SCRYWATCH_API_KEY"),
    scrywatch.WithService("api"),
    scrywatch.WithEnvironment("production"),
)

client.SetUserID("user-123")
client.Info(context.Background(), "User signed in", map[string]any{"plan": "pro"})
client.Warn(context.Background(), "Slow query", map[string]any{"duration_ms": 1450})
client.Error(context.Background(), "Payment failed", map[string]any{"order_id": "ord_456"})
```

## Functional options

| Option | Default | Description |
|--------|---------|-------------|
| `WithService(s)` | `""` | Service name attached to every event |
| `WithEnvironment(e)` | `""` | Environment tag (e.g. `"production"`) |
| `WithMaxRetries(n)` | `3` | Max retry attempts on 5xx / network errors |
| `WithTimeout(d)` | `5s` | Per-request timeout (ignored when using `WithHTTPClient`) |
| `WithHTTPClient(c)` | stdlib default | Provide your own `*http.Client` |

## LogEvent fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `Level` | string | yes | `error` \| `warn` \| `info` \| `debug` |
| `Type` | string | yes | `crash` \| `session` \| `navigation` \| `api_call` \| `custom` \| `cron` |
| `Message` | string | yes | Human-readable description |
| `Timestamp` | int64 | yes | Unix epoch **milliseconds** |
| `Service` | string | no | Overrides client-level service |
| `Environment` | string | no | Overrides client-level environment |
| `UserID` | string | no | User identifier |
| `DeviceType` | string | no | `"mobile"`, `"desktop"`, etc. |
| `Metadata` | `map[string]any` | no | Arbitrary JSON-serialisable data |

### Valid event types

`crash` `session` `navigation` `api_call` `custom` `cron`

> **Note:** `cron` is accepted by the ScryWatch backend but not yet exposed in the JS or Flutter SDKs.

## Retry behaviour

Retries up to `WithMaxRetries` times (default 3) on network errors or 5xx responses.
Backoff: exponential starting at 100 ms, doubling each attempt.
4xx responses return an error immediately — no retry.
````

- [ ] **Commit:**

```bash
git add packages/go/example_test.go packages/go/README.md
git commit -m "docs(go): add example and README"
```

---

## Chunk 3: Go HTTP Middleware (`packages/go-http`)

### File Map

| File | Purpose |
|------|---------|
| `packages/go-http/go.mod` | Module declaration, requires sdk-go with replace |
| `packages/go-http/go.sum` | Must be committed — has real dep hashes |
| `packages/go-http/middleware.go` | `LogSender` interface + `Middleware` func |
| `packages/go-http/middleware_test.go` | Behaviour tests |
| `packages/go-http/README.md` | Usage example |

---

### Task 3.1 — Module scaffold

**File:** Create `packages/go-http/go.mod`

- [ ] **Create `packages/go-http/go.mod`:**

```
module github.com/scrywatch/sdk-go-http

go 1.21

require github.com/scrywatch/sdk-go v0.0.0

replace github.com/scrywatch/sdk-go => ../go
```

- [ ] **Run `go mod tidy`:**

```bash
cd packages/go-http && go mod tidy
```

Expected: `go.sum` created with sdk-go hash entries.

- [ ] **Commit:**

```bash
git add packages/go-http/go.mod packages/go-http/go.sum
git commit -m "feat(go-http): scaffold module"
```

---

### Task 3.2 — Middleware with tests

**Files:** Create `packages/go-http/middleware.go`, `packages/go-http/middleware_test.go`

- [ ] **Write the failing tests** — `packages/go-http/middleware_test.go`:

```go
package scrywatchhttp_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	scrywatch "github.com/scrywatch/sdk-go"
	scrywatchhttp "github.com/scrywatch/sdk-go-http"
)

// mockLogger captures events sent to it.
type mockLogger struct {
	events []scrywatch.LogEvent
}

func (m *mockLogger) Send(_ context.Context, events []scrywatch.LogEvent) error {
	m.events = append(m.events, events...)
	return nil
}

func TestMiddleware_logsRequest(t *testing.T) {
	logger := &mockLogger{}

	handler := scrywatchhttp.Middleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/users", nil)
	rr  := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if len(logger.events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(logger.events))
	}

	e := logger.events[0]
	if e.Type != "api_call" {
		t.Errorf("expected type=api_call, got %s", e.Type)
	}
	if e.Level != "info" {
		t.Errorf("expected level=info for 200, got %s", e.Level)
	}
	if e.Metadata["method"] != "GET" {
		t.Errorf("expected method=GET, got %v", e.Metadata["method"])
	}
	if e.Metadata["path"] != "/api/users" {
		t.Errorf("expected path=/api/users, got %v", e.Metadata["path"])
	}
	if e.Metadata["status_code"] != 200 {
		t.Errorf("expected status_code=200, got %v", e.Metadata["status_code"])
	}
}

func TestMiddleware_levelFromStatus(t *testing.T) {
	cases := []struct {
		status int
		level  string
	}{
		{200, "info"},
		{201, "info"},
		{301, "info"},
		{400, "warn"},
		{404, "warn"},
		{500, "error"},
		{503, "error"},
	}

	for _, tc := range cases {
		logger := &mockLogger{}
		handler := scrywatchhttp.Middleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(tc.status)
		}))
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		rr  := httptest.NewRecorder()
		handler.ServeHTTP(rr, req)

		if got := logger.events[0].Level; got != tc.level {
			t.Errorf("status %d: expected level=%s, got %s", tc.status, tc.level, got)
		}
	}
}
```

- [ ] **Run test — expect failure:**

```bash
cd packages/go-http && go test ./... 2>&1 | head -5
```

Expected: `cannot find package "github.com/scrywatch/sdk-go-http"`

- [ ] **Implement `packages/go-http/middleware.go`:**

```go
// Package scrywatchhttp provides a net/http middleware that logs request
// details to ScryWatch via a LogSender (satisfied by *scrywatch.Client).
package scrywatchhttp

import (
	"context"
	"fmt"
	"net/http"
	"time"

	scrywatch "github.com/scrywatch/sdk-go"
)

// LogSender is satisfied by *scrywatch.Client.
// Defined over scrywatch.LogEvent so the interface is compatible without adapters.
type LogSender interface {
	Send(ctx context.Context, events []scrywatch.LogEvent) error
}

// Middleware returns an http.Handler middleware that logs each incoming
// request to ScryWatch as an api_call event.
//
// Level mapping: ≥500 → error, ≥400 → warn, else info.
//
// Usage:
//
//	mux := http.NewServeMux()
//	client := scrywatch.NewClient(endpoint, apiKey)
//	http.ListenAndServe(":8080", scrywatchhttp.Middleware(client)(mux))
func Middleware(logger LogSender) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

			next.ServeHTTP(rw, r)

			durationMs := time.Since(start).Milliseconds()
			level := levelFromStatus(rw.statusCode)

			event := scrywatch.LogEvent{
				Level:     level,
				Type:      "api_call",
				Message:   fmt.Sprintf("%s %s %d", r.Method, r.URL.Path, rw.statusCode),
				Timestamp: time.Now().UnixMilli(),
				Metadata: map[string]any{
					"method":      r.Method,
					"path":        r.URL.Path,
					"status_code": rw.statusCode,
					"duration_ms": durationMs,
				},
			}

			_ = logger.Send(r.Context(), []scrywatch.LogEvent{event})
		})
	}
}

func levelFromStatus(status int) string {
	switch {
	case status >= 500:
		return "error"
	case status >= 400:
		return "warn"
	default:
		return "info"
	}
}

// responseWriter wraps http.ResponseWriter to capture the written status code.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}
```

- [ ] **Run tests — expect all pass:**

```bash
cd packages/go-http && go test ./... -v
```

Expected: `PASS`

- [ ] **Create `packages/go-http/README.md`** with install instructions, `replace` directive note for monorepo development, and a minimal usage example showing `Middleware(client)(mux)`.

- [ ] **Commit:**

```bash
git add packages/go-http/middleware.go packages/go-http/middleware_test.go packages/go-http/README.md
git commit -m "feat(go-http): implement net/http middleware"
```

---

## Chunk 4: Laravel Package (`packages/laravel`)

### File Map

| File | Purpose |
|------|---------|
| `packages/laravel/composer.json` | Package manifest, requires scrywatch/php |
| `packages/laravel/config/scrywatch.php` | Publishable config file |
| `packages/laravel/src/ScryWatchServiceProvider.php` | Auto-registered service provider |
| `packages/laravel/src/ScryWatchChannel.php` | Monolog channel + handler |
| `packages/laravel/README.md` | Setup guide |

---

### Task 4.1 — Scaffold

- [ ] **Create `packages/laravel/composer.json`:**

```json
{
  "name": "scrywatch/laravel",
  "description": "Laravel integration for the ScryWatch PHP client",
  "type": "library",
  "license": "MIT",
  "require": {
    "php": "^8.1",
    "scrywatch/php": "^1.0",
    "laravel/framework": "^10.0 || ^11.0 || ^12.0"
  },
  "autoload": {
    "psr-4": {
      "ScryWatch\\Laravel\\": "src/"
    }
  },
  "extra": {
    "laravel": {
      "providers": [
        "ScryWatch\\Laravel\\ScryWatchServiceProvider"
      ]
    }
  }
}
```

- [ ] **Create `packages/laravel/.gitignore`:**

```
/vendor/
/composer.lock
```

- [ ] **Commit:**

```bash
git add packages/laravel/composer.json packages/laravel/.gitignore
git commit -m "feat(laravel): scaffold composer package"
```

---

### Task 4.2 — Config file

- [ ] **Create `packages/laravel/config/scrywatch.php`:**

```php
<?php

return [
    /*
    |--------------------------------------------------------------------------
    | ScryWatch Endpoint
    |--------------------------------------------------------------------------
    | The base URL for the ScryWatch ingest API.
    */
    'endpoint' => env('SCRYWATCH_ENDPOINT', 'https://api.scrywatch.com'),

    /*
    |--------------------------------------------------------------------------
    | API Key
    |--------------------------------------------------------------------------
    | Your ScryWatch project API key. Set SCRYWATCH_API_KEY in your .env file.
    */
    'api_key' => env('SCRYWATCH_API_KEY'),

    /*
    |--------------------------------------------------------------------------
    | Service Name
    |--------------------------------------------------------------------------
    | Tags every log event with this service name. Defaults to APP_NAME.
    */
    'service' => env('SCRYWATCH_SERVICE', env('APP_NAME', 'laravel')),

    /*
    |--------------------------------------------------------------------------
    | Environment
    |--------------------------------------------------------------------------
    | Tags every log event with this environment label. Defaults to APP_ENV.
    */
    'environment' => env('SCRYWATCH_ENV', env('APP_ENV', 'production')),

    /*
    |--------------------------------------------------------------------------
    | Max Retries
    |--------------------------------------------------------------------------
    | How many times to retry ingest on network error or 5xx response.
    */
    'max_retries' => (int) env('SCRYWATCH_MAX_RETRIES', 3),
];
```

- [ ] **Commit:**

```bash
git add packages/laravel/config/scrywatch.php
git commit -m "feat(laravel): add config file"
```

---

### Task 4.3 — ServiceProvider

- [ ] **Create `packages/laravel/src/ScryWatchServiceProvider.php`:**

```php
<?php
declare(strict_types=1);

namespace ScryWatch\Laravel;

use Illuminate\Support\ServiceProvider;
use ScryWatch\ScryWatchClient;

class ScryWatchServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->mergeConfigFrom(
            __DIR__ . '/../config/scrywatch.php',
            'scrywatch'
        );

        $this->app->singleton(ScryWatchClient::class, function ($app) {
            $config = $app['config']['scrywatch'];

            return new ScryWatchClient(
                endpoint:    $config['endpoint'],
                apiKey:      $config['api_key'] ?? '',
                service:     $config['service'] ?? null,
                environment: $config['environment'] ?? null,
                maxRetries:  (int) ($config['max_retries'] ?? 3),
            );
        });
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->publishes([
                __DIR__ . '/../config/scrywatch.php' => config_path('scrywatch.php'),
            ], 'scrywatch-config');
        }
    }
}
```

- [ ] **Commit:**

```bash
git add packages/laravel/src/ScryWatchServiceProvider.php
git commit -m "feat(laravel): add ServiceProvider"
```

---

### Task 4.4 — Monolog channel driver

- [ ] **Create `packages/laravel/src/ScryWatchChannel.php`:**

```php
<?php
declare(strict_types=1);

namespace ScryWatch\Laravel;

use Monolog\Handler\AbstractProcessingHandler;
use Monolog\Level;
use Monolog\Logger;
use Monolog\LogRecord;
use ScryWatch\ScryWatchClient;

/**
 * Laravel logging channel driver for ScryWatch.
 *
 * Add to config/logging.php channels:
 *
 *   'scrywatch' => [
 *       'driver' => 'custom',
 *       'via'    => \ScryWatch\Laravel\ScryWatchChannel::class,
 *   ],
 *
 * Then use: Log::channel('scrywatch')->info('Something happened');
 */
class ScryWatchChannel
{
    /**
     * @param  array<string,mixed>  $config  Laravel logging channel config array
     *
     * Resolves the ScryWatchClient singleton registered by ScryWatchServiceProvider
     * from the IoC container. Do NOT instantiate ScryWatchClient directly here — that
     * would bypass the endpoint/apiKey/service/environment config.
     */
    public function __invoke(array $config): Logger
    {
        $client  = app(ScryWatchClient::class);
        $handler = new ScryWatchMonologHandler($client);

        return new Logger('scrywatch', [$handler]);
    }
}

/**
 * Monolog handler that forwards log records to ScryWatch.
 *
 * Level mapping:
 *   DEBUG                              → debug
 *   INFO, NOTICE                       → info
 *   WARNING                            → warn
 *   ERROR, CRITICAL, ALERT, EMERGENCY  → error
 */
class ScryWatchMonologHandler extends AbstractProcessingHandler
{
    public function __construct(private readonly ScryWatchClient $client)
    {
        parent::__construct(Level::Debug, bubble: true);
    }

    protected function write(LogRecord $record): void
    {
        $level = match ($record->level) {
            Level::Debug                            => 'debug',
            Level::Info, Level::Notice              => 'info',
            Level::Warning                          => 'warn',
            default                                 => 'error', // Error, Critical, Alert, Emergency
        };

        $this->client->log($level, 'custom', $record->message, $record->context);
    }
}
```

- [ ] **Create `packages/laravel/README.md`** covering: `composer require`, `.env` keys, `php artisan vendor:publish --tag=scrywatch-config`, logging channel setup in `config/logging.php`, and basic usage via `Log::channel('scrywatch')`.

- [ ] **Commit:**

```bash
git add packages/laravel/src/ScryWatchChannel.php packages/laravel/README.md
git commit -m "feat(laravel): add Monolog channel driver and README"
```

---

## Chunk 5: Examples

### Task 5.1 — HTTP examples (`examples/http/`)

- [ ] **Create `examples/http/README.md`** with these curl examples:

```bash
# Single event
curl -X POST https://api.scrywatch.com/api/ingest \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [{
      "level": "info",
      "type": "custom",
      "message": "User signed in",
      "timestamp": 1741200000000,
      "user_id": "u_123",
      "service": "api",
      "environment": "production"
    }]
  }'

# Batch (up to 50 events)
curl -X POST https://api.scrywatch.com/api/ingest \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {"level":"error","type":"crash","message":"NullPointerException","timestamp":1741200000001,"service":"worker"},
      {"level":"info","type":"session","message":"session_start","timestamp":1741200000002,"user_id":"u_456"}
    ]
  }'

# OTLP trace (traces only — logs use /api/ingest above)
curl -X POST https://api.scrywatch.com/api/traces/otlp \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key":"service.name","value":{"stringValue":"api"}}]},
      "scopeSpans": [{"spans": [{
        "traceId": "abc123",
        "spanId":  "def456",
        "name":    "GET /users",
        "startTimeUnixNano": "1741200000000000000",
        "endTimeUnixNano":   "1741200000050000000",
        "status": {"code": 1}
      }]}]
    }]
  }'
```

- [ ] **Commit:**

```bash
git add examples/http/
git commit -m "docs(examples): add HTTP ingest curl examples"
```

---

### Task 5.2 — PHP examples (`examples/php/`)

- [ ] **Create `examples/php/basic.php`:**

```php
<?php
require __DIR__ . '/../../packages/php/vendor/autoload.php';

use ScryWatch\ScryWatchClient;

$client = new ScryWatchClient(
    endpoint:    'https://api.scrywatch.com',
    apiKey:      getenv('SCRYWATCH_API_KEY') ?: 'YOUR_API_KEY',
    service:     'php-example',
    environment: 'development',
);

$client->setUserId('user-123');
$client->info('Application started');
$client->warn('Cache miss', ['key' => 'user:profile:123', 'ttl_ms' => 0]);
$client->error('Payment failed', ['order_id' => 'ord_789', 'reason' => 'card_declined']);

// Explicit type control
$client->log('info', 'cron', 'Daily report job completed', ['duration_ms' => 4200]);

// Batch send
use ScryWatch\LogEvent;
$client->send([
    new LogEvent(level: 'debug', type: 'custom', message: 'step 1', timestamp: (int)(microtime(true) * 1000)),
    new LogEvent(level: 'debug', type: 'custom', message: 'step 2', timestamp: (int)(microtime(true) * 1000)),
]);

echo "Events sent.\n";
```

- [ ] **Create `examples/php/README.md`** with install instructions and link to `basic.php`.

- [ ] **Commit:**

```bash
git add examples/php/
git commit -m "docs(examples): add PHP usage examples"
```

---

### Task 5.3 — Go examples (`examples/go/`)

- [ ] **Create `examples/go/go.mod`:**

```
module scrywatch/examples/go

go 1.21

require github.com/scrywatch/sdk-go v0.0.0

replace github.com/scrywatch/sdk-go => ../../packages/go
```

- [ ] **Run `go mod tidy`:**

```bash
cd examples/go && go mod tidy
```

Expected: `go.sum` created.

- [ ] **Create `examples/go/basic/main.go`:**

```go
package main

import (
	"context"
	"fmt"
	"os"

	scrywatch "github.com/scrywatch/sdk-go"
)

func main() {
	client := scrywatch.NewClient(
		"https://api.scrywatch.com",
		os.Getenv("SCRYWATCH_API_KEY"),
		scrywatch.WithService("go-example"),
		scrywatch.WithEnvironment("development"),
	)

	client.SetUserID("user-123")

	if err := client.Info(context.Background(), "Application started", nil); err != nil {
		fmt.Fprintln(os.Stderr, "scrywatch:", err)
	}

	_ = client.Warn(context.Background(), "Cache miss", map[string]any{
		"key":    "user:profile:123",
		"ttl_ms": 0,
	})

	_ = client.Error(context.Background(), "Payment failed", map[string]any{
		"order_id": "ord_789",
		"reason":   "card_declined",
	})

	// Explicit batch
	_ = client.Send(context.Background(), []scrywatch.LogEvent{
		{Level: "info", Type: "cron", Message: "daily report done",
			Timestamp: 1741200000000, Metadata: map[string]any{"duration_ms": 4200}},
	})

	fmt.Println("Events sent.")
}
```

- [ ] **Create `examples/go/slog/main.go`** — a `slog.Handler` adapter:

```go
// Package main demonstrates a slog.Handler adapter that forwards
// log/slog records to a *scrywatch.Client.
package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	scrywatch "github.com/scrywatch/sdk-go"
)

// ScryWatchHandler implements slog.Handler.
type ScryWatchHandler struct {
	client *scrywatch.Client
}

func (h *ScryWatchHandler) Enabled(_ context.Context, level slog.Level) bool { return true }

func (h *ScryWatchHandler) Handle(ctx context.Context, r slog.Record) error {
	level := slogLevelToScryWatch(r.Level)
	attrs := make(map[string]any, r.NumAttrs())
	r.Attrs(func(a slog.Attr) bool {
		attrs[a.Key] = a.Value.Any()
		return true
	})
	return h.client.Send(ctx, []scrywatch.LogEvent{{
		Level:     level,
		Type:      "custom",
		Message:   r.Message,
		Timestamp: r.Time.UnixMilli(),
		Metadata:  attrs,
	}})
}

func (h *ScryWatchHandler) WithAttrs(_ []slog.Attr) slog.Handler { return h }
func (h *ScryWatchHandler) WithGroup(_ string) slog.Handler       { return h }

func slogLevelToScryWatch(l slog.Level) string {
	switch {
	case l >= slog.LevelError:
		return "error"
	case l >= slog.LevelWarn:
		return "warn"
	case l >= slog.LevelInfo:
		return "info"
	default:
		return "debug"
	}
}

func main() {
	client := scrywatch.NewClient(
		"https://api.scrywatch.com",
		os.Getenv("SCRYWATCH_API_KEY"),
		scrywatch.WithService("go-slog-example"),
	)

	logger := slog.New(&ScryWatchHandler{client: client})
	slog.SetDefault(logger)

	slog.Info("slog adapter active", "started_at", time.Now().Format(time.RFC3339))
	slog.Warn("something unusual", "threshold", 0.95)
}
```

- [ ] **Commit:**

```bash
git add examples/go/go.mod examples/go/go.sum examples/go/basic/ examples/go/slog/
git commit -m "docs(examples): add Go basic and slog adapter examples"
```

---

### Task 5.4 — Laravel examples (`examples/laravel/`)

- [ ] **Create `examples/laravel/README.md`** showing:
  1. `composer require scrywatch/laravel` and `scrywatch/php`
  2. Publish config: `php artisan vendor:publish --tag=scrywatch-config`
  3. `.env` keys: `SCRYWATCH_API_KEY`, `SCRYWATCH_SERVICE`, `SCRYWATCH_ENV`
  4. `config/logging.php` channel stanza
  5. Usage: `Log::channel('scrywatch')->info(...)` and `app(ScryWatchClient::class)->send(...)`

- [ ] **Commit:**

```bash
git add examples/laravel/
git commit -m "docs(examples): add Laravel integration example"
```

---

## Chunk 6: OTel Assets

### Task 6.1 — Collector traces config

- [ ] **Create `otel/collector/traces-with-scrywatch.yaml`:**

```yaml
# otel/collector/traces-with-scrywatch.yaml
#
# Routes OTLP traces to ScryWatch.
# ScryWatch supports OTLP HTTP/JSON for TRACES ONLY.
# For logs: use the ScryWatch SDK directly (POST /api/ingest).
#
# Required environment variables:
#   SCRYWATCH_API_KEY   — your project API key
#   SCRYWATCH_ENDPOINT  — e.g. https://api.scrywatch.com

receivers:
  otlp:
    protocols:
      # The Collector accepts gRPC and HTTP from your instrumented services.
      # ScryWatch only accepts OTLP HTTP/JSON — the otlphttp exporter below
      # handles that translation automatically (gRPC → HTTP at export time).
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 256
  batch:
    timeout: 5s
    send_batch_size: 50

exporters:
  otlphttp/scrywatch:
    endpoint: ${env:SCRYWATCH_ENDPOINT}
    headers:
      Authorization: "Bearer ${env:SCRYWATCH_API_KEY}"
    traces_endpoint: ${env:SCRYWATCH_ENDPOINT}/api/traces/otlp
    retry_on_failure:
      enabled: true
      initial_interval: 1s
      max_interval: 30s
    sending_queue:
      enabled: true
      num_consumers: 4
      queue_size: 100

service:
  pipelines:
    traces:
      receivers:  [otlp]
      processors: [memory_limiter, batch]
      exporters:  [otlphttp/scrywatch]
```

- [ ] **Create `otel/collector/full-pipeline.yaml`** — traces path above plus a log collection stub:

```yaml
# otel/collector/full-pipeline.yaml
#
# Traces: routed to ScryWatch OTLP endpoint.
# Logs:   collected from container stdout, written to local file for demonstration.
#
# ⚠️  OTLP log ingest is NOT yet supported by ScryWatch.
#     Use the ScryWatch SDK directly from application code for log shipping.
#     This log pipeline shows collection and parsing only.
#     Replace the 'file' exporter with your preferred log sink.

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  filelog:
    include: [/var/log/containers/*.log]
    operators:
      - type: json_parser
        timestamp:
          parse_from: attributes.time
          layout: "%Y-%m-%dT%H:%M:%S.%LZ"

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 384
  batch:
    timeout: 5s
    send_batch_size: 50

exporters:
  otlphttp/scrywatch:
    endpoint: ${env:SCRYWATCH_ENDPOINT}
    headers:
      Authorization: "Bearer ${env:SCRYWATCH_API_KEY}"
    traces_endpoint: ${env:SCRYWATCH_ENDPOINT}/api/traces/otlp
    retry_on_failure:
      enabled: true

  # Log demonstration sink — replace with your preferred forwarder.
  # See /kubernetes/logs-only/ for the Kubernetes equivalent (uses debug/stdout).
  file:
    path: /var/log/scrywatch-collector-logs.json

service:
  pipelines:
    traces:
      receivers:  [otlp]
      processors: [memory_limiter, batch]
      exporters:  [otlphttp/scrywatch]
    logs:
      receivers:  [filelog]
      processors: [memory_limiter, batch]
      exporters:  [file]
```

- [ ] **Commit:**

```bash
git add otel/collector/
git commit -m "docs(otel): add collector config templates"
```

---

### Task 6.2 — OTel mappings doc

- [ ] **Create `otel/mappings/README.md`** with three sections:

**Section 1 — Traces field mapping** (from `normalizeOtlp()` in the backend):

| OTLP JSON Field | ScryWatch Field | Notes |
|---|---|---|
| `resource.attributes["service.name"]` | `service` | Defaults to `"unknown"` |
| `span.traceId` | `trace_id` | Direct copy |
| `span.spanId` | `span_id` | Direct copy |
| `span.parentSpanId` | `parent_span_id` | Null if empty (root span) |
| `span.name` | `name` | Direct copy |
| `span.startTimeUnixNano` | `start_time` | Divided by 1,000,000 → ms |
| `span.endTimeUnixNano` | `end_time` | Divided by 1,000,000 → ms |
| `span.status.code === 2` | `status: "error"` | All other codes → `"ok"` |
| `span.attributes[*]` | `attributes` | Stored as JSON |
| `span.events` | `events` | Stored as JSON array |

**Section 2 — Log-trace correlation:** Code snippet showing how to extract `trace_id` and `span_id` from the active OTel span and pass them to the ScryWatch SDK.

**Section 3 — Aspirational (clearly marked):** Table of future signals (OTLP logs, OTLP metrics) with status "Not yet implemented."

- [ ] **Create `otel/php/README.md`** — PHP OTel integration notes showing `opentelemetry-php` SDK for traces alongside `scrywatch/php` for logs, with manual trace ID extraction.

- [ ] **Create `otel/go/README.md`** — Go OTel integration notes showing `go.opentelemetry.io/otel` for traces alongside `sdk-go` for logs, with manual trace/span ID extraction from `trace.SpanFromContext(ctx)`.

- [ ] **Commit:**

```bash
git add otel/mappings/ otel/php/ otel/go/
git commit -m "docs(otel): add field mappings and PHP/Go integration notes"
```

---

## Chunk 7: Kubernetes Assets

### Task 7.1 — logs-only DaemonSet

- [ ] **Create `kubernetes/logs-only/collector-configmap.yaml`:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-logs-config
  namespace: observability
data:
  config.yaml: |
    # ⚠️  ScryWatch does not yet support OTLP log ingest.
    #     This pipeline demonstrates collection and parsing of container logs only.
    #     For production log shipping to ScryWatch, use the ScryWatch SDK directly.
    #     Replace the 'debug' exporter with your preferred log forwarder.

    receivers:
      filelog:
        include: [/var/log/pods/**/*.log]
        operators:
          - type: json_parser
            timestamp:
              parse_from: attributes.time
              layout: "%Y-%m-%dT%H:%M:%SZ"

    processors:
      memory_limiter:
        check_interval: 1s
        limit_mib: 128
      batch:
        timeout: 5s

    exporters:
      debug:
        verbosity: normal

    service:
      pipelines:
        logs:
          receivers:  [filelog]
          processors: [memory_limiter, batch]
          exporters:  [debug]
```

- [ ] **Create `kubernetes/logs-only/collector-daemonset.yaml`:**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector-logs
  namespace: observability
spec:
  selector:
    matchLabels:
      app: otel-collector-logs
  template:
    metadata:
      labels:
        app: otel-collector-logs
    spec:
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector-contrib:0.96.0
          args: ["--config=/etc/otel/config.yaml"]
          volumeMounts:
            - name: config
              mountPath: /etc/otel
            - name: varlog
              mountPath: /var/log
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: otel-collector-logs-config
        - name: varlog
          hostPath:
            path: /var/log
```

- [ ] **Commit:**

```bash
git add kubernetes/logs-only/
git commit -m "docs(kubernetes): add logs-only collector DaemonSet"
```

---

### Task 7.2 — logs-and-traces DaemonSet

- [ ] **Create `kubernetes/logs-and-traces/collector-configmap.yaml`** — same log pipeline as above plus OTLP traces pipeline routing to ScryWatch via `${SCRYWATCH_API_KEY}` and `${SCRYWATCH_ENDPOINT}` env vars.

- [ ] **Create `kubernetes/logs-and-traces/collector-daemonset.yaml`** — same DaemonSet with the addition of OTLP port 4317/4318 containerPorts and a `secretRef` for the ScryWatch secret.

- [ ] **Create `kubernetes/raw-yaml/scrywatch-secret.yaml`:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: scrywatch-credentials
  namespace: observability
type: Opaque
stringData:
  api-key: "YOUR_SCRYWATCH_API_KEY"       # TODO: replace
  endpoint: "https://api.scrywatch.com"  # TODO: replace if self-hosted
```

- [ ] **Create `kubernetes/raw-yaml/collector-configmap.yaml`** — parameterised version of the traces config referencing the secret.

- [ ] **Create `kubernetes/raw-yaml/collector-daemonset.yaml`** — DaemonSet using `envFrom` the scrywatch-credentials Secret to inject `SCRYWATCH_API_KEY` and `SCRYWATCH_ENDPOINT`. Mirrors the structure from `kubernetes/logs-and-traces/collector-daemonset.yaml` with OTLP ports 4317/4318 exposed. Namespace: `observability`.

- [ ] **Commit:**

```bash
git add kubernetes/logs-and-traces/ kubernetes/raw-yaml/
git commit -m "docs(kubernetes): add logs-and-traces and raw-yaml manifests"
```

---

### Task 7.3 — Helm values

- [ ] **Create `kubernetes/helm/values-logs-only.yaml`** — snippet for `open-telemetry/opentelemetry-collector` chart, filelog receiver, debug exporter, with honest comment about log ingest status.

- [ ] **Create `kubernetes/helm/values-logs-and-traces.yaml`** — snippet adding OTLP receiver and `otlphttp` exporter pointing at `${SCRYWATCH_ENDPOINT}` with auth header.

- [ ] **Create `kubernetes/helm/README.md`** — two-line install commands using `helm install otel-collector open-telemetry/opentelemetry-collector -f values-logs-and-traces.yaml`.

- [ ] **Commit:**

```bash
git add kubernetes/helm/
git commit -m "docs(kubernetes): add Helm values snippets"
```

---

## Chunk 8: Docs

### Task 8.1 — Quickstart decision tree

- [ ] **Create `docs/quickstart/README.md`:**

| My stack | Integration path | Start here |
|----------|-----------------|-----------|
| JavaScript / Node.js / browser | JS SDK | `/js/README.md` |
| Flutter / Dart | Flutter SDK | `/flutter/README.md` |
| PHP (standalone) | PHP package | `/packages/php/README.md` |
| PHP (Laravel) | Laravel package | `/packages/laravel/README.md` |
| Go | Go package | `/packages/go/README.md` |
| Go (net/http middleware) | Go HTTP middleware | `/packages/go-http/README.md` |
| Any stack (raw HTTP) | HTTP ingest | `/examples/http/README.md` |
| OpenTelemetry | OTel collector | `/docs/otel/README.md` |
| Kubernetes | Kubernetes deployment | `/docs/kubernetes/README.md` |

- [ ] **Commit:**

```bash
git add docs/quickstart/
git commit -m "docs: add quickstart decision tree"
```

---

### Task 8.2 — PHP, Go, OTel, Kubernetes docs

- [ ] **Create `docs/php/README.md`** — PHP quickstart matching `/packages/php/README.md` Quickstart section, plus link to the package and Laravel integration.

- [ ] **Create `docs/go/README.md`** — Go quickstart matching `/packages/go/README.md` plus link to go-http middleware.

- [ ] **Create `docs/otel/README.md`** — OTel overview: signal support table, pointer to `/otel/collector/`, pointer to `/otel/mappings/`, honest note on log/metric gap.

- [ ] **Create `docs/kubernetes/README.md`** — Kubernetes overview: two paths (Helm vs raw YAML), links to `/kubernetes/helm/` and `/kubernetes/raw-yaml/`, prerequisite (kubectl + Helm installed, ScryWatch API key in a Secret).

- [ ] **Commit:**

```bash
git add docs/php/ docs/go/ docs/otel/ docs/kubernetes/
git commit -m "docs: add PHP, Go, OTel, and Kubernetes quickstart docs"
```

---

### Task 8.3 — Update root README

- [ ] **Update `/README.md`** to add a section listing all integration paths with links. Keep it short — the quickstart doc has the details.

- [ ] **Commit:**

```bash
git add README.md
git commit -m "docs: update root README with all integration paths"
```
