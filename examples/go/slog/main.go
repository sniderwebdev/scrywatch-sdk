// Package main demonstrates a slog.Handler adapter that forwards
// log/slog records to a *scrywatch.Client.
package main

import (
	"context"
	"log/slog"
	"os"
	"time"

	scrywatch "github.com/scrywatch/sdk-go"
)

// ScryWatchHandler implements slog.Handler.
type ScryWatchHandler struct {
	client *scrywatch.Client
}

func (h *ScryWatchHandler) Enabled(_ context.Context, level slog.Level) bool { return true }

func (h *ScryWatchHandler) Handle(ctx context.Context, r slog.Record) error {
	level := slogLevelToScryWatch(r.Level)
	attrs := make(map[string]any, r.NumAttrs())
	r.Attrs(func(a slog.Attr) bool {
		attrs[a.Key] = a.Value.Any()
		return true
	})
	return h.client.Send(ctx, []scrywatch.LogEvent{{
		Level:     level,
		Type:      "custom",
		Message:   r.Message,
		Timestamp: r.Time.UnixMilli(),
		Metadata:  attrs,
	}})
}

func (h *ScryWatchHandler) WithAttrs(_ []slog.Attr) slog.Handler { return h }
func (h *ScryWatchHandler) WithGroup(_ string) slog.Handler       { return h }

func slogLevelToScryWatch(l slog.Level) string {
	switch {
	case l >= slog.LevelError:
		return "error"
	case l >= slog.LevelWarn:
		return "warn"
	case l >= slog.LevelInfo:
		return "info"
	default:
		return "debug"
	}
}

func main() {
	client := scrywatch.NewClient(
		"https://api.scrywatch.com",
		os.Getenv("SCRYWATCH_API_KEY"),
		scrywatch.WithService("go-slog-example"),
	)

	logger := slog.New(&ScryWatchHandler{client: client})
	slog.SetDefault(logger)

	slog.Info("slog adapter active", "started_at", time.Now().Format(time.RFC3339))
	slog.Warn("something unusual", "threshold", 0.95)
}
