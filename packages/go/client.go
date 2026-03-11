package scrywatch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"time"
)

// Client sends log events to ScryWatch.
// Safe for concurrent use.
type Client struct {
	endpoint    string
	apiKey      string
	httpClient  *http.Client
	service     string
	environment string
	maxRetries  int
	userID      atomic.Value // stores string
}

// NewClient creates a new ScryWatch client.
//
//	client := scrywatch.NewClient("https://api.scrywatch.com", "YOUR_API_KEY",
//	    scrywatch.WithService("api"),
//	    scrywatch.WithEnvironment("production"),
//	)
func NewClient(endpoint, apiKey string, opts ...Option) *Client {
	cfg := &config{
		maxRetries: 3,
		timeout:    5 * time.Second,
	}
	for _, o := range opts {
		o(cfg)
	}
	if cfg.httpClient == nil {
		cfg.httpClient = &http.Client{Timeout: cfg.timeout}
	}
	return &Client{
		endpoint:    endpoint,
		apiKey:      apiKey,
		httpClient:  cfg.httpClient,
		service:     cfg.service,
		environment: cfg.environment,
		maxRetries:  cfg.maxRetries,
	}
}

// SetUserID attaches a user ID to all subsequent log events.
// Safe for concurrent use.
func (c *Client) SetUserID(id string) {
	c.userID.Store(id)
}

func (c *Client) userIDStr() string {
	v := c.userID.Load()
	if v == nil {
		return ""
	}
	str, ok := v.(string)
	if !ok {
		return ""
	}
	return str
}

// Info sends an info-level custom event.
func (c *Client) Info(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "info", "custom", message, metadata)
}

// Warn sends a warn-level custom event.
func (c *Client) Warn(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "warn", "custom", message, metadata)
}

// Error sends an error-level custom event.
func (c *Client) Error(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "error", "custom", message, metadata)
}

// Debug sends a debug-level custom event.
func (c *Client) Debug(ctx context.Context, message string, metadata map[string]any) error {
	return c.log(ctx, "debug", "custom", message, metadata)
}

func (c *Client) log(ctx context.Context, level, typ, message string, metadata map[string]any) error {
	event := LogEvent{
		Level:       level,
		Type:        typ,
		Message:     message,
		Timestamp:   time.Now().UnixMilli(),
		UserID:      c.userIDStr(),
		Environment: c.environment,
		Service:     c.service,
		Metadata:    metadata,
	}
	return c.Send(ctx, []LogEvent{event})
}

// Send posts a batch of events to ScryWatch ingest.
// Retries on network errors and 5xx responses (up to MaxRetries).
// 4xx responses return an error immediately without retrying.
func (c *Client) Send(ctx context.Context, events []LogEvent) error {
	payload, err := json.Marshal(map[string]any{"events": events})
	if err != nil {
		return fmt.Errorf("scrywatch: marshal: %w", err)
	}

	url := strings.TrimRight(c.endpoint, "/") + "/api/ingest"

	backoff := 100 * time.Millisecond
	var lastErr error

	for attempt := 0; attempt <= c.maxRetries; attempt++ {
		if attempt > 0 {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(backoff):
			}
			backoff *= 2
		}

		status, err := c.doRequest(ctx, url, payload)
		if err == nil && status == 202 {
			return nil
		}
		if err == nil && status >= 400 && status < 500 {
			return fmt.Errorf("scrywatch: ingest rejected: HTTP %d", status)
		}
		if err != nil {
			lastErr = fmt.Errorf("scrywatch: request: %w", err)
		} else {
			lastErr = fmt.Errorf("scrywatch: ingest: HTTP %d", status)
		}
	}

	return lastErr
}

func (c *Client) doRequest(ctx context.Context, url string, body []byte) (int, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return 0, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return 0, fmt.Errorf("do request: %w", err)
	}
	resp.Body.Close()
	return resp.StatusCode, nil
}
