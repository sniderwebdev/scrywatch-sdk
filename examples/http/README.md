# ScryWatch HTTP Ingest Examples

Raw curl examples for the ScryWatch ingest API. No SDK required.

## Single event

```bash
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
```

Expected response: `HTTP 202 Accepted` (empty body).

## Batch (up to 50 events)

```bash
curl -X POST https://api.scrywatch.com/api/ingest \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "events": [
      {"level":"error","type":"crash","message":"NullPointerException","timestamp":1741200000001,"service":"worker"},
      {"level":"info","type":"session","message":"session_start","timestamp":1741200000002,"user_id":"u_456"}
    ]
  }'
```

## OTLP traces (traces only)

ScryWatch supports OTLP HTTP/JSON for **traces only**. Logs must use `/api/ingest` above.

```bash
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

## Event fields reference

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `level` | yes | string | `error` \| `warn` \| `info` \| `debug` |
| `type` | yes | string | `crash` \| `session` \| `navigation` \| `api_call` \| `custom` \| `cron` |
| `message` | yes | string | Human-readable description |
| `timestamp` | yes | number | Unix epoch milliseconds |
| `user_id` | no | string | User identifier |
| `session_id` | no | string | Session identifier |
| `service` | no | string | Service name |
| `environment` | no | string | Environment label |
| `device_type` | no | string | Device type |
| `trace_id` | no | string | OTel trace ID |
| `span_id` | no | string | OTel span ID |
| `metadata` | no | object | Arbitrary JSON data |
