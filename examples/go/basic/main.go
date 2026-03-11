package main

import (
	"context"
	"fmt"
	"os"

	scrywatch "github.com/scrywatch/sdk-go"
)

func main() {
	client := scrywatch.NewClient(
		"https://api.scrywatch.com",
		os.Getenv("SCRYWATCH_API_KEY"),
		scrywatch.WithService("go-example"),
		scrywatch.WithEnvironment("development"),
	)

	client.SetUserID("user-123")

	if err := client.Info(context.Background(), "Application started", nil); err != nil {
		fmt.Fprintln(os.Stderr, "scrywatch:", err)
	}

	_ = client.Warn(context.Background(), "Cache miss", map[string]any{
		"key":    "user:profile:123",
		"ttl_ms": 0,
	})

	_ = client.Error(context.Background(), "Payment failed", map[string]any{
		"order_id": "ord_789",
		"reason":   "card_declined",
	})

	// Explicit batch
	_ = client.Send(context.Background(), []scrywatch.LogEvent{
		{Level: "info", Type: "cron", Message: "daily report done",
			Timestamp: 1741200000000, Metadata: map[string]any{"duration_ms": 4200}},
	})

	fmt.Println("Events sent.")
}
