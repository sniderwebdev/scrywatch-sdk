package scrywatch

import (
	"net/http"
	"time"
)

type config struct {
	httpClient  *http.Client
	service     string
	environment string
	maxRetries  int
	timeout     time.Duration
}

// Option configures a Client.
type Option func(*config)

// WithHTTPClient sets the HTTP client used for requests.
// Defaults to a client with a 5-second timeout.
func WithHTTPClient(c *http.Client) Option {
	return func(cfg *config) { cfg.httpClient = c }
}

// WithService tags every event with the given service name.
func WithService(s string) Option {
	return func(cfg *config) { cfg.service = s }
}

// WithEnvironment tags every event with the given environment label.
func WithEnvironment(e string) Option {
	return func(cfg *config) { cfg.environment = e }
}

// WithMaxRetries sets how many times to retry on network error or 5xx response.
// Default is 3.
func WithMaxRetries(n int) Option {
	return func(cfg *config) { cfg.maxRetries = n }
}

// WithTimeout sets the per-request HTTP timeout.
// Default is 5 seconds. This option has no effect when a custom
// HTTP client is provided via WithHTTPClient — configure the
// timeout on that client directly instead.
func WithTimeout(d time.Duration) Option {
	return func(cfg *config) { cfg.timeout = d }
}
