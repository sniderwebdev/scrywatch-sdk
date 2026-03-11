package scrywatch

// LogEvent is a single structured log event sent to ScryWatch.
//
// Wire format uses snake_case JSON; omitempty fields are omitted when zero-value.
// Valid Levels: error, warn, info, debug.
// Valid Types:  crash, session, navigation, api_call, custom, cron.
// Note: cron is accepted by the backend but not yet in the JS/Flutter SDKs.
type LogEvent struct {
	Level       string         `json:"level"`
	Type        string         `json:"type"`
	Message     string         `json:"message"`
	Timestamp   int64          `json:"timestamp"` // Unix milliseconds
	UserID      string         `json:"user_id,omitempty"`
	SessionID   string         `json:"session_id,omitempty"`
	Environment string         `json:"environment,omitempty"`
	Service     string         `json:"service,omitempty"`
	DeviceType  string         `json:"device_type,omitempty"`
	TraceID     string         `json:"trace_id,omitempty"`
	SpanID      string         `json:"span_id,omitempty"`
	Metadata    map[string]any `json:"metadata,omitempty"`
}
