# ScryWatch Go

Quick guide for integrating ScryWatch into Go applications.

## SDK

```bash
go get github.com/scrywatch/sdk-go
```

```go
import scrywatch "github.com/scrywatch/sdk-go"

client := scrywatch.NewClient(
    "https://api.scrywatch.com",
    os.Getenv("SCRYWATCH_API_KEY"),
    scrywatch.WithService("my-app"),
    scrywatch.WithEnvironment("production"),
)

client.SetUserID("user-123")
client.Info(ctx, "User signed in", nil)
client.Error(ctx, "Payment failed", map[string]any{"order_id": "ord_789"})
```

See [`/packages/go/README.md`](/packages/go/README.md) for full API reference.

## net/http Middleware

```bash
go get github.com/scrywatch/sdk-go-http
```

```go
import (
    scrywatch "github.com/scrywatch/sdk-go"
    scrywatchhttp "github.com/scrywatch/sdk-go-http"
)

client := scrywatch.NewClient("https://api.scrywatch.com", os.Getenv("SCRYWATCH_API_KEY"))
mux := http.NewServeMux()
http.ListenAndServe(":8080", scrywatchhttp.Middleware(client)(mux))
```

See [`/packages/go-http/README.md`](/packages/go-http/README.md) for full middleware reference.
