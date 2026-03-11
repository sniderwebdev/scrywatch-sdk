package scrywatch_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	scrywatch "github.com/scrywatch/sdk-go"
)

func newTestServer(t *testing.T, statusCode int, assertFn func(*http.Request)) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if assertFn != nil {
			assertFn(r)
		}
		w.WriteHeader(statusCode)
	}))
}

func TestClient_Info_success(t *testing.T) {
	srv := newTestServer(t, 202, nil)
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "test-key")
	if err := client.Info(context.Background(), "hello", nil); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestClient_Send_usesEventsEnvelope(t *testing.T) {
	var body map[string]any

	srv := newTestServer(t, 202, func(r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		json.Unmarshal(b, &body) //nolint
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key")
	_ = client.Info(context.Background(), "envelope check", nil)

	if _, ok := body["events"]; !ok {
		t.Fatal("request body missing 'events' key")
	}
	events := body["events"].([]any)
	if len(events) != 1 {
		t.Fatalf("expected 1 event, got %d", len(events))
	}
}

func TestClient_Send_setsAuthHeader(t *testing.T) {
	// assertFn is a closure that captures t; t.Errorf is safe here because
	// httptest handlers run synchronously relative to the client.Do() call.
	srv := newTestServer(t, 202, func(r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer my-api-key" {
			t.Errorf("wrong Authorization header: got %q, want %q", got, "Bearer my-api-key")
		}
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "my-api-key")
	_ = client.Info(context.Background(), "auth test", nil)
}

func TestClient_Send_postsToIngestPath(t *testing.T) {
	srv := newTestServer(t, 202, func(r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/api/ingest") {
			t.Errorf("wrong path: got %q, want suffix /api/ingest", r.URL.Path)
		}
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key")
	_ = client.Info(context.Background(), "path test", nil)
}

func TestClient_Send_4xxFailsImmediately(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(400)
	}))
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key", scrywatch.WithMaxRetries(3))
	err := client.Info(context.Background(), "bad", nil)

	if err == nil {
		t.Fatal("expected error for 4xx, got nil")
	}
	if callCount != 1 {
		t.Fatalf("expected 1 call (no retry on 4xx), got %d", callCount)
	}
}

func TestClient_Send_5xxRetries(t *testing.T) {
	callCount := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		w.WriteHeader(503)
	}))
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key", scrywatch.WithMaxRetries(2))
	err := client.Info(context.Background(), "retry test", nil)

	if err == nil {
		t.Fatal("expected error after exhausted retries, got nil")
	}
	if callCount != 3 { // initial + 2 retries
		t.Fatalf("expected 3 calls (initial + 2 retries), got %d", callCount)
	}
}

func TestClient_SetUserID_attachesToEvents(t *testing.T) {
	var body map[string]any

	srv := newTestServer(t, 202, func(r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		json.Unmarshal(b, &body) //nolint
	})
	defer srv.Close()

	client := scrywatch.NewClient(srv.URL, "key")
	client.SetUserID("user-99")
	_ = client.Info(context.Background(), "with user", nil)

	events := body["events"].([]any)
	event := events[0].(map[string]any)
	if event["user_id"] != "user-99" {
		t.Fatalf("expected user_id=user-99, got %v", event["user_id"])
	}
}
