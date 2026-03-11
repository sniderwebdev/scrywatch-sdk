# github.com/scrywatch/sdk-go-http

`net/http` middleware for [ScryWatch](https://scrywatch.com) that logs each incoming request as an `api_call` event.

## Requirements

- Go 1.21+
- [`github.com/scrywatch/sdk-go`](../go)

## Installation

```bash
go get github.com/scrywatch/sdk-go-http
go get github.com/scrywatch/sdk-go
```

> **Monorepo development:** If working in this repository locally, `go.mod` uses a `replace` directive:
> ```
> replace github.com/scrywatch/sdk-go => ../go
> ```
> Remove or update this directive when consuming published versions.

## Usage

```go
import (
    scrywatch    "github.com/scrywatch/sdk-go"
    scrywatchhttp "github.com/scrywatch/sdk-go-http"
)

client := scrywatch.NewClient(
    "https://api.scrywatch.com",
    os.Getenv("SCRYWATCH_API_KEY"),
    scrywatch.WithService("api"),
)

mux := http.NewServeMux()
mux.HandleFunc("/", yourHandler)

http.ListenAndServe(":8080", scrywatchhttp.Middleware(client)(mux))
```

## Level mapping

| HTTP status range | ScryWatch level |
|-------------------|----------------|
| < 400             | `info`         |
| 400–499           | `warn`         |
| ≥ 500             | `error`        |

## Metadata logged per request

| Key | Type | Description |
|-----|------|-------------|
| `method` | string | HTTP method (GET, POST, …) |
| `path` | string | Request path |
| `status_code` | int | HTTP response status code |
| `duration_ms` | int64 | Request duration in milliseconds |

## Custom logger

`Middleware` accepts any type satisfying `LogSender`:

```go
type LogSender interface {
    Send(ctx context.Context, events []scrywatch.LogEvent) error
}
```

`*scrywatch.Client` satisfies this interface directly.
