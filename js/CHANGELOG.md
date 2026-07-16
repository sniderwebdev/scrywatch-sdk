# Changelog

## 1.1.0

### Added

- Anonymous `device_id`: a persistent random UUID generated on first use, stored in `localStorage['scrywatch_device_id']` (falls back to an in-memory id when `localStorage` is unavailable/blocked, e.g. SSR or privacy mode — never throws). Sent as a top-level `device_id` field on every `/api/ingest` request body, alongside `events`.
- `getDeviceId()` — returns the current session's device id.
- `identify(userId, traits?)` — tags subsequent events with `userId` (same mechanism as `setUserId`) and upserts `{ user_id, traits }` to `POST {endpoint}/api/identify` with the `Authorization: Bearer <apiKey>` header. Fire-and-forget: network/HTTP failures are caught and logged via `console.warn`, never thrown to the caller.

## 1.0.0

Initial release.
