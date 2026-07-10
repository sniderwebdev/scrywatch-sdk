# Changelog

## 1.0.0

Initial release.

- `LogClient` — buffered log ingestion to ScryWatch (`POST /api/ingest`) with an automatic periodic flush.
- Session tracking via `startSession()` / `endSession()`.
- Log levels (`error`, `warn`, `info`, `debug`) and event types, with optional structured `metadata`.
- Manual `flush()` and `dispose()` for controlled shutdown.
