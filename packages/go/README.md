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
| `SessionID` | string | no | Session identifier |
| `TraceID` | string | no | OTel trace ID for log-trace correlation |
| `SpanID` | string | no | OTel span ID for log-trace correlation |
| `DeviceType` | string | no | `"mobile"`, `"desktop"`, etc. |
| `Metadata` | `map[string]any` | no | Arbitrary JSON-serialisable data |

### Valid event types

`crash` `session` `navigation` `api_call` `custom` `cron`

> **Note:** `cron` is accepted by the ScryWatch backend but not yet exposed in the JS or Flutter SDKs.

## Retry behaviour

Retries up to `WithMaxRetries` times (default 3) on network errors or 5xx responses.
Backoff: exponential starting at 100 ms, doubling each attempt.
4xx responses return an error immediately — no retry.
