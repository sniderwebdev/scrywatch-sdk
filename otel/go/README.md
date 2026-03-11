# ScryWatch + OpenTelemetry (Go)

Use [`go.opentelemetry.io/otel`](https://opentelemetry.io/docs/languages/go/) for **traces** and `github.com/scrywatch/sdk-go` for **logs**.

## Install

```bash
go get github.com/scrywatch/sdk-go
go get go.opentelemetry.io/otel
go get go.opentelemetry.io/otel/exporters/otlphttp/otlptrace
```

## Usage

```go
import (
    "context"
    "go.opentelemetry.io/otel/trace"
    scrywatch "github.com/scrywatch/sdk-go"
)

func handleRequest(ctx context.Context, client *scrywatch.Client) {
    // Extract correlation IDs from active OTel span
    span := trace.SpanFromContext(ctx)
    sc := span.SpanContext()

    _ = client.Send(ctx, []scrywatch.LogEvent{{
        Level:   "info",
        Type:    "api_call",
        Message: "request processed",
        TraceID: sc.TraceID().String(),
        SpanID:  sc.SpanID().String(),
        Metadata: map[string]any{"endpoint": "/users"},
    }})
}
```

## Architecture

```
Your Go app
  ├─ go.opentelemetry.io/otel → OTLP exporter → ScryWatch /api/traces/otlp  (traces)
  └─ github.com/scrywatch/sdk-go              → ScryWatch /api/ingest        (logs)
```

> **Note:** OTLP log ingest is not yet supported. Use `sdk-go` directly for logs.
