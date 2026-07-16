# Changelog

## 0.3.0

Fixed

- **A new session is now started on every app launch.** Previously the session id was persisted in `shared_preferences` and reused across launches, but the frame sequence counter (`_seq`) resets to 0 on each cold start — so a relaunch re-uploaded frames `0, 1, 2…` into the *same* session, overwriting the prior run's frames in storage and double-counting the session's `frame_count`. Session ids are no longer persisted; each launch is a distinct session (the FullStory/Sentry model), keeping the frame sequence a clean 0…N per session.

Changed

- `rotateSession()` and `clearSession()` no longer read or write the `replay_session_id` preference (session ids are no longer persisted). Their observable behavior — rotate mints a fresh id and resets the sequence; clear empties the session so no further frames upload — is unchanged. Call `rotateSession()` on a mid-session user change and `clearSession()` on sign-out as before.

## 0.2.0

Added

- Anonymous, persistent `device_id`: generated on first use (random v4-ish UUID) and persisted via `shared_preferences` under `scrywatch_device_id` — the same key used by the `scrywatch` logging SDK, so an app using both SDKs shares one device id. Falls back to an in-memory id (never persisted, never throws) if `shared_preferences` is unavailable. Included as a top-level `device_id` field in every segment upload's `x-replay-meta` once loaded.
- `ScrywatchReplay.setUser(String? userId)`: sets (or clears, with `null`) the current user id, included as `user_id` in subsequent segment uploads' `x-replay-meta`. Not persisted — call it with the signed-in user's id on sign-in and `null` on sign-out. This is what powers the ScryWatch dashboard's "User Card" (who a replay session belongs to).

## 0.1.0

Initial preview release.

- `ScrywatchReplay` facade: `init()`, `setConsent()`, `stop()`, `wrap()`.
- Deny-by-default masking engine: `ScrywatchTag`, `ScrywatchMask`, `ScrywatchReveal`.
- Always-on PII floor: email, Luhn-validated card/PAN, SSN, and phone-number text detection, `obscureText` fields, and platform-view/native-texture surfaces (WebView, camera, video) — masked in every mode, never revealable.
- Remote mask policy fetch (`blocklist`/`strict` modes, `tag`/`widgetType`/`textPattern` rules) with a fail-safe fallback to the built-in blocklist default on any fetch error.
- Post-capture bitmap masking — the live UI is never altered; only the captured frame is redacted before upload.
- Fail-safe full-frame occlusion when a hard-mask region's geometry can't be resolved for a given frame.
- Recorder hardening: frame uploads are now wrapped in a try/catch + 10s timeout so a network failure is counted as a dropped frame instead of crashing the host app; `ScrywatchReplay.rotateSession()`/`clearSession()` let apps rotate the replay session on sign-in and clear it on sign-out so frames are never co-mingled across users; a guard prevents any frame from being uploaded with an empty session id; capture now pauses automatically while the app is backgrounded (`AppLifecycleState.paused`/`hidden`) and resumes when it returns to the foreground, and per-frame debug logging was removed to avoid console spam.
