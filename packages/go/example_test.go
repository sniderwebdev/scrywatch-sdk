package scrywatch_test

import (
	"context"

	scrywatch "github.com/scrywatch/sdk-go"
)

func Example() {
	client := scrywatch.NewClient(
		"https://api.scrywatch.com",
		"YOUR_API_KEY",
		scrywatch.WithService("api"),
		scrywatch.WithEnvironment("production"),
	)

	client.SetUserID("user-123")

	_ = client.Info(context.Background(), "User signed in", map[string]any{
		"plan": "pro",
	})

	_ = client.Send(context.Background(), []scrywatch.LogEvent{
		{Level: "warn", Type: "api_call", Message: "slow downstream", Timestamp: 1741200000000,
			Metadata: map[string]any{"duration_ms": 1450}},
	})
}
