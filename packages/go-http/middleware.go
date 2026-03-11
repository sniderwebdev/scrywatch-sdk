// Package scrywatchhttp provides a net/http middleware that logs request
// details to ScryWatch via a LogSender (satisfied by *scrywatch.Client).
package scrywatchhttp

import (
	"context"
	"fmt"
	"net/http"
	"time"

	scrywatch "github.com/scrywatch/sdk-go"
)

// LogSender is satisfied by *scrywatch.Client.
// Defined over scrywatch.LogEvent so the interface is compatible without adapters.
type LogSender interface {
	Send(ctx context.Context, events []scrywatch.LogEvent) error
}

// Middleware returns an http.Handler middleware that logs each incoming
// request to ScryWatch as an api_call event.
//
// Level mapping: >=500 -> error, >=400 -> warn, else info.
//
// Usage:
//
//	mux := http.NewServeMux()
//	client := scrywatch.NewClient(endpoint, apiKey)
//	http.ListenAndServe(":8080", scrywatchhttp.Middleware(client)(mux))
func Middleware(logger LogSender) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rw := &responseWriter{ResponseWriter: w, statusCode: http.StatusOK}

			next.ServeHTTP(rw, r)

			durationMs := time.Since(start).Milliseconds()
			level := levelFromStatus(rw.statusCode)

			event := scrywatch.LogEvent{
				Level:     level,
				Type:      "api_call",
				Message:   fmt.Sprintf("%s %s %d", r.Method, r.URL.Path, rw.statusCode),
				Timestamp: time.Now().UnixMilli(),
				Metadata: map[string]any{
					"method":      r.Method,
					"path":        r.URL.Path,
					"status_code": rw.statusCode,
					"duration_ms": durationMs,
				},
			}

			_ = logger.Send(r.Context(), []scrywatch.LogEvent{event})
		})
	}
}

func levelFromStatus(status int) string {
	switch {
	case status >= 500:
		return "error"
	case status >= 400:
		return "warn"
	default:
		return "info"
	}
}

// responseWriter wraps http.ResponseWriter to capture the written status code.
type responseWriter struct {
	http.ResponseWriter
	statusCode int
}

func (rw *responseWriter) WriteHeader(code int) {
	rw.statusCode = code
	rw.ResponseWriter.WriteHeader(code)
}
