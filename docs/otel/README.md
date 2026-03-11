# ScryWatch — OpenTelemetry

## Signal support

| Signal | Status | Path |
|--------|--------|------|
| Traces (OTLP HTTP/JSON) | ✅ Supported | `POST /api/traces/otlp` |
| Logs (OTLP) | ❌ Not supported | Use `/api/ingest` via SDK |
| Metrics (OTLP) | ❌ Not supported | — |

## Collector configuration

Ready-to-use OTel Collector configs:

- [`/otel/collector/traces-with-scrywatch.yaml`](/otel/collector/traces-with-scrywatch.yaml) — traces only
- [`/otel/collector/full-pipeline.yaml`](/otel/collector/full-pipeline.yaml) — traces + log collection demo

## Field mappings

See [`/otel/mappings/README.md`](/otel/mappings/README.md) for the OTLP → ScryWatch field mapping table and log-trace correlation examples.

## Language integration notes

- Go: [`/otel/go/README.md`](/otel/go/README.md)
- PHP: [`/otel/php/README.md`](/otel/php/README.md)
