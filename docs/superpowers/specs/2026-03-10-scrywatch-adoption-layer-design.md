# ScryWatch Adoption Layer Expansion — Design Spec

**Date:** 2026-03-10
**Status:** Approved
**Scope:** Add PHP, Go, Laravel, and Go HTTP middleware packages; HTTP/PHP/Go/Laravel examples; OTel collector configs and mapping docs; Kubernetes deployment assets; developer docs.

---

## 1. Background

The `scrywatch-sdk` repository currently contains `/js` (TypeScript) and `/flutter` (Dart) SDKs. The goal is to expand it into a credible adoption layer for PHP, Go, OpenTelemetry, and Kubernetes without creating empty or misleading packages.

### Existing conventions (must be preserved)

- **Ingest endpoint:** `POST {endpoint}/api/ingest`
- **Auth:** `Authorization: Bearer {apiKey}`
- **Success response:** HTTP 202 Accepted
- **Event wire format:** JSON, snake_case fields
- **Event schema:** `{ timestamp, level, type, message, user_id?, session_id?, environment?, service?, device_type?, metadata?, trace_id?, span_id? }`
- **Valid levels:** `error | warn | info | debug`
- **Valid types (existing SDKs):** `crash | session | navigation | api_call | custom`
- **Valid types (backend also accepts):** `cron` — supported by the ingest route but not yet exposed in the JS or Flutter SDKs. New PHP and Go packages **should** include `cron` as a valid type since they target the backend contract directly. Document it clearly in each package's README.
- **Batch max:** 50 events per request
- **Traces endpoint:** `POST {endpoint}/api/traces/otlp` — OTLP HTTP/JSON, traces only
- **Metrics endpoint:** `POST {endpoint}/api/metrics` — native format, exists in the backend; no OTLP support

---

## 2. Repo Layout

```
/js                       (existing — untouched)
/flutter                  (existing — untouched)

/packages/
  php/                    Composer package: scrywatch/php
  go/                     Go module: github.com/scrywatch/sdk-go
  laravel/                Composer package: scrywatch/laravel
  go-http/                Go module: github.com/scrywatch/sdk-go-http

/examples/
  http/                   Raw HTTP / curl examples
  php/                    PHP client usage examples
  go/                     Go client usage examples
  laravel/                Laravel integration example

/otel/
  collector/              OTel Collector YAML config templates
  mappings/               OTel concept → ScryWatch field mapping documentation
  php/                    PHP OTel integration notes
  go/                     Go OTel integration notes

/kubernetes/
  helm/                   Helm values snippets for collector-based deployment
  raw-yaml/               Raw YAML for manual deployment
  logs-only/              Minimal logs-only collector deployment
  logs-and-traces/        Collector for traces + logs

/docs/
  quickstart/             Integration decision tree / entry point
  php/                    PHP quickstart
  go/                     Go quickstart
  otel/                   OTel overview and adoption path
  kubernetes/             Kubernetes overview and install options
```

Existing `/js` and `/flutter` remain at root for backward compatibility. All new installable packages go under `/packages/`.

---

## 3. PHP Package — `scrywatch/php`

**Path:** `/packages/php`
**Purpose:** Lightweight, synchronous PHP client for sending structured log events to ScryWatch over HTTP ingest.

### 3.1 File Structure

```
packages/php/
├── composer.json
├── README.md
├── src/
│   ├── ScryWatchClient.php
│   ├── LogEvent.php
│   ├── ScryWatchException.php
│   └── Http/
│       └── CurlHttpClient.php
└── .gitignore
```

### 3.2 Dependencies

`composer.json` `require`:
- `php: ^8.1`
- `psr/http-client: ^1.0` (interface only — no runtime code)
- `psr/http-factory: ^1.0` (interface only)

No `guzzlehttp/guzzle` or other HTTP runtime in `require`. `CurlHttpClient` (internal) is the zero-dep fallback using PHP's `curl` extension.

`require-dev`: `phpunit/phpunit`.

### 3.3 Constructor

```php
new ScryWatchClient(
    endpoint: string,
    apiKey: string,
    service: ?string = null,
    environment: ?string = null,
    maxRetries: int = 3,
    httpClient: ?Psr\Http\Client\ClientInterface = null,
    requestFactory: ?Psr\Http\Message\RequestFactoryInterface = null,
    streamFactory: ?Psr\Http\Message\StreamFactoryInterface = null,
)
```

When `httpClient` is `null`, `CurlHttpClient` is used. When PSR-17 factories are `null`, internal implementations are used.

### 3.4 Public API

```php
$client->info(string $message, array $metadata = []): void
$client->warn(string $message, array $metadata = []): void
$client->error(string $message, array $metadata = []): void
$client->debug(string $message, array $metadata = []): void
$client->log(string $level, string $type, string $message, array $metadata = []): void
$client->send(array $events): void   // low-level batch send (array of LogEvent or raw arrays)
$client->setUserId(string $id): void
```

`info/warn/error/debug` send type `custom`. `log()` allows explicit type control.

### 3.5 Retry Behavior

Up to `maxRetries` attempts on network exception or non-202 response. Linear backoff: 500 ms × attempt number (attempt 1 waits 500 ms, attempt 2 waits 1000 ms, attempt 3 waits 1500 ms). Throws `ScryWatchException` after the final failure.

### 3.6 PHP Buffering Note

No background buffer. PHP is synchronous and request/response. `send()` fires immediately. For queue workers or long-running scripts, callers accumulate events in an array and call `send()` once.

---

## 4. Go Package — `sdk-go`

**Path:** `/packages/go`
**Module:** `github.com/scrywatch/sdk-go`
**Purpose:** Lightweight Go client for sending structured log events to ScryWatch.

### 4.1 File Structure

```
packages/go/
├── go.mod
├── README.md
├── client.go
├── event.go
├── options.go
└── example_test.go
```

Zero external dependencies. Uses standard library only (`net/http`, `encoding/json`, `context`). `go.sum` is generated by `go mod tidy` and will be empty for a zero-dep module.

### 4.2 Constructor

```go
client := scrywatch.NewClient(
    "https://api.scrywatch.com",
    "YOUR_API_KEY",
    scrywatch.WithService("api"),
    scrywatch.WithEnvironment("production"),
    scrywatch.WithHTTPClient(myClient),   // *http.Client; defaults to http.DefaultClient
    scrywatch.WithMaxRetries(3),
    scrywatch.WithTimeout(5 * time.Second),
)
```

Functional options pattern via `Option` type.

### 4.3 Public API

```go
func (c *Client) Info(ctx context.Context, message string, metadata map[string]any) error
func (c *Client) Warn(ctx context.Context, message string, metadata map[string]any) error
func (c *Client) Error(ctx context.Context, message string, metadata map[string]any) error
func (c *Client) Debug(ctx context.Context, message string, metadata map[string]any) error
func (c *Client) Send(ctx context.Context, events []LogEvent) error
func (c *Client) SetUserID(id string)
```

All methods accept `context.Context` for cancellation and deadline propagation.

### 4.4 Retry Behavior

Exponential backoff: 100 ms base, doubles per attempt, up to `maxRetries`. Retries on network errors and non-202 responses. Returns error after final attempt.

### 4.5 `LogEvent` Type

```go
type LogEvent struct {
    Level       string         `json:"level"`
    Type        string         `json:"type"`
    Message     string         `json:"message"`
    Timestamp   int64          `json:"timestamp"`   // milliseconds
    UserID      string         `json:"user_id,omitempty"`
    SessionID   string         `json:"session_id,omitempty"`
    Environment string         `json:"environment,omitempty"`
    Service     string         `json:"service,omitempty"`
    TraceID     string         `json:"trace_id,omitempty"`
    SpanID      string         `json:"span_id,omitempty"`
    Metadata    map[string]any `json:"metadata,omitempty"`
}
```

---

## 5. Go HTTP Middleware — `sdk-go-http`

**Path:** `/packages/go-http`
**Module:** `github.com/scrywatch/sdk-go-http`
**Purpose:** Tiny `net/http`-compatible middleware for logging HTTP requests via ScryWatch.

### 5.1 File Structure

```
packages/go-http/
├── go.mod
├── README.md
└── middleware.go
```

`sdk-go-http` imports `github.com/scrywatch/sdk-go` as a direct dependency. This is the only external dependency. The `replace` directive in `go.mod` points to `../go` for local development; downstream consumers reference the published version normally.

### 5.2 Interface and Middleware

`LogSender` is defined in terms of `sdk-go.LogEvent` so that `*scrywatch.Client` satisfies it without an adapter:

```go
import scrywatch "github.com/scrywatch/sdk-go"

// LogSender is satisfied by *scrywatch.Client.
type LogSender interface {
    Send(ctx context.Context, events []scrywatch.LogEvent) error
}

func Middleware(logger LogSender) func(http.Handler) http.Handler
```

The middleware wraps any `http.Handler`. For each request it records: method, path, status code, duration. Level follows the existing SDK convention: ≥500 → `error`, ≥400 → `warn`, else `info`. Event type is `api_call`.

**Why this design:** Defining `LogSender` over `scrywatch.LogEvent` (rather than a local struct) is the only way `*scrywatch.Client` can satisfy the interface at compile time. A local minimal struct would create a different Go type, breaking the interface. The dependency on `sdk-go` is explicit, appropriate, and expected — both modules are maintained together in this repo.

---

## 6. Laravel Package — `scrywatch/laravel`

**Path:** `/packages/laravel`
**Purpose:** Laravel-friendly integration layer over `scrywatch/php`. Provides auto-discovered ServiceProvider and an optional Monolog channel driver.

### 6.1 File Structure

```
packages/laravel/
├── composer.json
├── README.md
├── config/
│   └── scrywatch.php
└── src/
    ├── ScryWatchServiceProvider.php
    └── ScryWatchChannel.php
```

`composer.json` requires: `scrywatch/php: ^1.0`, `laravel/framework: ^10.0 || ^11.0`.

### 6.2 ServiceProvider

Auto-registered via `extra.laravel.providers` in `composer.json`. Merges and publishes config. Binds `ScryWatchClient` as a singleton in the service container.

### 6.3 Config File

```php
// config/scrywatch.php
return [
    'endpoint'    => env('SCRYWATCH_ENDPOINT', 'https://api.scrywatch.com'),
    'api_key'     => env('SCRYWATCH_API_KEY'),
    'service'     => env('SCRYWATCH_SERVICE', env('APP_NAME', 'laravel')),
    'environment' => env('SCRYWATCH_ENV', env('APP_ENV', 'production')),
    'max_retries' => env('SCRYWATCH_MAX_RETRIES', 3),
];
```

### 6.4 Monolog Channel Driver

`ScryWatchChannel` implements a custom Monolog handler factory compatible with `config/logging.php` channels. This makes ScryWatch usable as a named logging channel without additional wiring.

**Monolog → ScryWatch level mapping:**

| Monolog Level | ScryWatch Level |
|---|---|
| DEBUG | `debug` |
| INFO, NOTICE | `info` |
| WARNING | `warn` |
| ERROR, CRITICAL, ALERT, EMERGENCY | `error` |

NOTICE collapses to `info` because ScryWatch has no NOTICE equivalent and it carries the same severity semantics in practice. CRITICAL, ALERT, and EMERGENCY all collapse to `error` — the highest ScryWatch severity.

---

## 7. OTel Assets

### 7.1 Supported Signal Matrix (honest)

| Signal  | OTLP Support | Backend endpoint                                  |
|---------|-------------|---------------------------------------------------|
| Traces  | ✅ HTTP/JSON | `POST /api/traces/otlp`                           |
| Logs    | ❌ Not yet  | `POST /api/ingest` (native) — use SDK directly    |
| Metrics | ❌ Not yet  | `POST /api/metrics` (native) — no OTLP equivalent |
| gRPC    | ❌ No plans | HTTP/JSON only; gRPC not implemented              |

`/api/metrics` exists in the backend (native format: `{ host, service?, environment?, timestamp?, metrics: [{ name, value, unit? }], metadata? }`), but it has no OTLP ingest path and is out of scope for this expansion.

All OTel documentation must reflect this table. Nothing claims OTLP log or metric support.

### 7.2 `/otel/collector/`

Two YAML templates:

1. **`traces-with-scrywatch.yaml`** — Collector receives OTLP (gRPC + HTTP), exports traces to `POST /api/traces/otlp` via `otlphttp` exporter. Clear `${env:SCRYWATCH_API_KEY}` and `${env:SCRYWATCH_ENDPOINT}` placeholders. `batch` and `memory_limiter` processors included.

2. **`full-pipeline.yaml`** — Same traces path, plus `filelog` receiver tailing container stdout and a generic HTTP/file exporter for logs. The log pipeline explicitly notes in comments that OTLP log ingest is not yet implemented and that direct SDK usage is the recommended path.

### 7.3 `/otel/mappings/`

`README.md` with three sections:
- **Traces mapping table** — OTLP JSON field → ScryWatch span field (from `normalizeOtlp()` implementation)
- **Log-trace correlation** — How to add `trace_id`/`span_id` to SDK log events manually
- **Aspirational** — Explicitly marked section for future OTLP logs/metrics support

### 7.4 `/otel/php/` and `/otel/go/`

Integration notes: how to instrument with the OTel SDK for traces while using the ScryWatch SDK for logs, with code snippets showing manual correlation (extract `trace_id`/`span_id` from the active OTel span and pass them to the ScryWatch client).

---

## 8. Kubernetes Assets

All Kubernetes examples deploy an **OTel Collector** as the integration point. No custom ScryWatch operator or CRD.

### 8.1 `/kubernetes/logs-only/`

Minimal collector `DaemonSet` + `ConfigMap`. Uses `filelog` receiver tailing `/var/log/pods/**/*.log`. The log pipeline uses the `debug` exporter (writes parsed log records to stdout) as the demonstration sink. A prominent comment block explains:

1. ScryWatch does not yet support OTLP log ingest.
2. For production log shipping to ScryWatch, use the ScryWatch SDK directly from application code.
3. The `debug` exporter here shows the collector receiving and parsing structured container logs — replace it with a forwarding exporter of your choice (e.g., to a log aggregator that feeds the SDK, or a future ScryWatch OTLP logs endpoint).

### 8.2 `/kubernetes/logs-and-traces/`

Collector `DaemonSet` (filelog + OTLP receiver) that forwards traces to `POST /api/traces/otlp`. Clear note about log signal maturity.

### 8.3 `/kubernetes/helm/`

Two `values.yaml` snippets for `open-telemetry/opentelemetry-collector` Helm chart:
- `values-logs-only.yaml`
- `values-logs-and-traces.yaml`

### 8.4 `/kubernetes/raw-yaml/`

Three files: `collector-configmap.yaml`, `collector-deployment.yaml`, `scrywatch-secret.yaml`. All use `# TODO: replace` comments for API key and endpoint.

---

## 9. Examples

| Path | Contents |
|------|----------|
| `/examples/http/` | `curl` examples for `/api/ingest`, `/api/traces/otlp`; JSON event shapes; batch example |
| `/examples/php/` | Basic PHP client usage; optional Monolog-style example |
| `/examples/go/` | Basic Go client usage; `slog`-compatible wrapper example |
| `/examples/laravel/` | Minimal Laravel channel config and log call example |

---

## 10. Docs

Each doc is a focused `README.md` in its directory:

| Path | Contents |
|------|----------|
| `/docs/quickstart/` | Decision table: stack → integration path → link |
| `/docs/php/` | PHP quickstart (install, configure, send first event) |
| `/docs/go/` | Go quickstart (install, configure, send first event) |
| `/docs/otel/` | OTel overview, signal support table, collector setup link |
| `/docs/kubernetes/` | Kubernetes overview, Helm vs raw-YAML paths, link to `/kubernetes/` |

---

## 11. Out of Scope

- Python, Ruby, Java, .NET SDKs
- ScryWatch backend changes
- Native OTLP log or metric ingest (documented as aspirational only)
- Helm chart authoring (values snippets only — references the upstream `opentelemetry-collector` chart)
- CI/CD pipeline changes
