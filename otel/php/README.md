# ScryWatch + OpenTelemetry (PHP)

Use the [OpenTelemetry PHP SDK](https://opentelemetry.io/docs/languages/php/) for **traces** and `scrywatch/php` for **logs**.

## Install

```bash
composer require scrywatch/php
composer require open-telemetry/sdk
```

## Usage

```php
use OpenTelemetry\SDK\SdkBuilder;
use ScryWatch\ScryWatchClient;

// Traces: configured via OTel PHP SDK pointing to your collector
// Logs: use ScryWatch directly
$client = new ScryWatchClient(
    endpoint: 'https://api.scrywatch.com',
    apiKey:   getenv('SCRYWATCH_API_KEY'),
    service:  'my-app',
);

// Correlate a log with an active OTel span
$span = OpenTelemetry\API\Globals::tracerProvider()
    ->getTracer('my-app')
    ->spanBuilder('handle-request')
    ->startSpan();

$ctx = $span->getContext();
$client->log('info', 'api_call', 'Request handled', [
    'trace_id' => $ctx->getTraceId(),
    'span_id'  => $ctx->getSpanId(),
]);

$span->end();
```

## Architecture

```
Your PHP app
  ├─ OTel PHP SDK → OTLP exporter → ScryWatch /api/traces/otlp  (traces)
  └─ scrywatch/php                → ScryWatch /api/ingest        (logs)
```

> **Note:** OTLP log ingest is not yet supported. Use `scrywatch/php` directly for logs.
