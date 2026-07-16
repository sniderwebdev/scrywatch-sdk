# Changelog

## 1.1.0

### Added

- Anonymous `device_id`: a persistent random UUID generated on first use, stored via `shared_preferences` under `scrywatch_device_id` (falls back to an in-memory id if `shared_preferences` is unavailable — never throws). Sent as a top-level `device_id` field on every `/api/ingest` request body, alongside `events`.
- `getDeviceId()` — `Future<String>` that resolves to the current device id once loaded/generated.
- `identify(String userId, {Map<String, dynamic>? traits})` — tags subsequent events with `userId` (same mechanism as `setUserId`) and upserts `{ user_id, traits }` to `POST {endpoint}/api/identify` with the `Authorization: Bearer <apiKey>` header. Never throws — network/HTTP failures are caught internally.
- `LogClient` now accepts an optional `httpClient` (`http.Client`) constructor parameter for dependency injection in tests.

## 1.0.0

Initial release.

- `LogClient` — buffered log ingestion to ScryWatch (`POST /api/ingest`) with an automatic periodic flush.
- Session tracking via `startSession()` / `endSession()`.
- Log levels (`error`, `warn`, `info`, `debug`) and event types, with optional structured `metadata`.
- Manual `flush()` and `dispose()` for controlled shutdown.
