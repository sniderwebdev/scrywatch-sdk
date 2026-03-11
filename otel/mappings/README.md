# OTel → ScryWatch Field Mappings

## Section 1 — Traces field mapping

Derived from the `normalizeOtlp()` function in the ScryWatch backend.

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

## Section 2 — Log-trace correlation

ScryWatch log events accept optional `trace_id` and `span_id` fields for correlation with traces.

**PHP example:**
```php
use OpenTelemetry\API\Trace\Propagation\TraceContextPropagator;
use ScryWatch\ScryWatchClient;

// Extract from active OTel span
$span = \OpenTelemetry\API\Globals::tracerProvider()
    ->getTracer('app')
    ->spanBuilder('operation')
    ->startSpan();

$context = $span->getContext();
$client->log('info', 'api_call', 'Downstream call', [
    'trace_id' => $context->getTraceId(),
    'span_id'  => $context->getSpanId(),
]);
```

**Go example:**
```go
import (
    "go.opentelemetry.io/otel/trace"
    scrywatch "github.com/scrywatch/sdk-go"
)

func handler(ctx context.Context, client *scrywatch.Client) {
    span := trace.SpanFromContext(ctx)
    sc := span.SpanContext()

    _ = client.Send(ctx, []scrywatch.LogEvent{{
        Level:   "info",
        Type:    "api_call",
        Message: "downstream call",
        TraceID: sc.TraceID().String(),
        SpanID:  sc.SpanID().String(),
    }})
}
```

## Section 3 — Aspirational signals (not yet implemented)

The following OTel signals are **not yet supported** by ScryWatch:

| Signal | OTLP endpoint | Status |
|--------|---------------|--------|
| Logs | `/api/logs/otlp` | Not yet implemented — use `/api/ingest` |
| Metrics | `/api/metrics/otlp` | Not yet implemented — use `/api/metrics` |
