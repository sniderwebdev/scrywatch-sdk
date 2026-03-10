# @scrywatch/sdk

Official JavaScript/TypeScript SDK for [ScryWatch](https://scrywatch.com) — zero dependencies, automatic event batching, session tracking.

## Install

```bash
npm install @scrywatch/sdk
# pnpm add @scrywatch/sdk
# bun add @scrywatch/sdk
```

## Quick Start

```typescript
import { LogMonitor } from '@scrywatch/sdk';

const monitor = new LogMonitor({
  endpoint: 'https://api.scrywatch.com',
  apiKey: 'YOUR_API_KEY',
  service: 'my-app',
  environment: 'production',
});

monitor.startSession();
monitor.info('App started');
monitor.logNavigation('/home');

// Errors
try {
  await fetchData();
} catch (err) {
  monitor.logError(err as Error);
}
```

## API

| Method | Description |
|--------|-------------|
| `new LogMonitor(config)` | Initialize with endpoint, apiKey, optional service/environment |
| `startSession()` | Begin a new user session |
| `endSession()` | End the current session |
| `setUserId(id)` | Tag subsequent logs with a user ID |
| `info(message, metadata?)` | Log at info level |
| `warn(message, metadata?)` | Log at warn level |
| `error(message, metadata?)` | Log at error level |
| `debug(message, metadata?)` | Log at debug level |
| `logNavigation(route)` | Log a navigation event |
| `logApiCall(method, url, status, durationMs)` | Log an API call |
| `logError(error, metadata?)` | Log an Error object with stack trace |
| `await flush()` | Manually flush buffered events — returns `Promise<void>` |
| `dispose()` | Stop timer and initiate flush (fire-and-forget — call `await flush()` first for guaranteed delivery) |

## Config

```typescript
interface LogMonitorConfig {
  endpoint: string;        // ScryWatch API base URL
  apiKey: string;          // Project API key
  service?: string;        // Service name tag
  environment?: string;    // Environment tag (e.g. "production")
  bufferSize?: number;     // Max events before auto-flush (default: 50)
  flushInterval?: number;  // Auto-flush interval ms (default: 10000)
  maxRetries?: number;     // Retry attempts on failure (default: 3)
}
```

## License

MIT
