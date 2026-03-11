package scrywatchhttp_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	scrywatch "github.com/scrywatch/sdk-go"
	scrywatchhttp "github.com/scrywatch/sdk-go-http"
)

// mockLogger captures events sent to it.
type mockLogger struct {
	events []scrywatch.LogEvent
}

func (m *mockLogger) Send(_ context.Context, events []scrywatch.LogEvent) error {
	m.events = append(m.events, events...)
	return nil
}

func TestMiddleware_logsRequest(t *testing.T) {
	logger := &mockLogger{}

	handler := scrywatchhttp.Middleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
	}))

	req := httptest.NewRequest(http.MethodGet, "/api/users", nil)
	rr  := httptest.NewRecorder()
	handler.ServeHTTP(rr, req)

	if len(logger.events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(logger.events))
	}

	e := logger.events[0]
	if e.Type != "api_call" {
		t.Errorf("expected type=api_call, got %s", e.Type)
	}
	if e.Level != "info" {
		t.Errorf("expected level=info for 200, got %s", e.Level)
	}
	if e.Metadata["method"] != "GET" {
		t.Errorf("expected method=GET, got %v", e.Metadata["method"])
	}
	if e.Metadata["path"] != "/api/users" {
		t.Errorf("expected path=/api/users, got %v", e.Metadata["path"])
	}
	if e.Metadata["status_code"] != 200 {
		t.Errorf("expected status_code=200, got %v", e.Metadata["status_code"])
	}
}

func TestMiddleware_levelFromStatus(t *testing.T) {
	cases := []struct {
		status int
		level  string
	}{
		{200, "info"},
		{201, "info"},
		{301, "info"},
		{400, "warn"},
		{404, "warn"},
		{500, "error"},
		{503, "error"},
	}

	for _, tc := range cases {
		logger := &mockLogger{}
		handler := scrywatchhttp.Middleware(logger)(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(tc.status)
		}))
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		rr  := httptest.NewRecorder()
		handler.ServeHTTP(rr, req)

		if got := logger.events[0].Level; got != tc.level {
			t.Errorf("status %d: expected level=%s, got %s", tc.status, tc.level, got)
		}
	}
}
