# Changelog

## 0.1.0

Initial preview release.

- `ScrywatchReplay` facade: `init()`, `setConsent()`, `stop()`, `wrap()`.
- Deny-by-default masking engine: `ScrywatchTag`, `ScrywatchMask`, `ScrywatchReveal`.
- Always-on PII floor: email, Luhn-validated card/PAN, SSN, and phone-number text detection, `obscureText` fields, and platform-view/native-texture surfaces (WebView, camera, video) — masked in every mode, never revealable.
- Remote mask policy fetch (`blocklist`/`strict` modes, `tag`/`widgetType`/`textPattern` rules) with a fail-safe fallback to the built-in blocklist default on any fetch error.
- Post-capture bitmap masking — the live UI is never altered; only the captured frame is redacted before upload.
- Fail-safe full-frame occlusion when a hard-mask region's geometry can't be resolved for a given frame.
- Recorder hardening: frame uploads are now wrapped in a try/catch + 10s timeout so a network failure is counted as a dropped frame instead of crashing the host app; `ScrywatchReplay.rotateSession()`/`clearSession()` let apps rotate the replay session on sign-in and clear it on sign-out so frames are never co-mingled across users; a guard prevents any frame from being uploaded with an empty session id; capture now pauses automatically while the app is backgrounded (`AppLifecycleState.paused`/`hidden`) and resumes when it returns to the foreground, and per-frame debug logging was removed to avoid console spam.
