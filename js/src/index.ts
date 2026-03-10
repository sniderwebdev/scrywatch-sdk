import type { LogMonitorConfig, LogLevel, LogType, LogEvent } from './types';
import { EventBuffer } from './buffer';
import { detectDeviceType } from './device';

export type { LogMonitorConfig, LogLevel, LogType, LogEvent };

function generateId(): string {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return Array.from(bytes).map(b => b.toString(16).padStart(2, '0')).join('');
}

export class LogMonitor {
  private buffer: EventBuffer;
  private sessionId: string | null = null;
  private userId: string | null = null;
  private service: string | undefined;
  private environment: string | undefined;
  private deviceType: string;

  constructor(config: LogMonitorConfig) {
    this.service = config.service;
    this.environment = config.environment;
    this.deviceType = detectDeviceType();

    this.buffer = new EventBuffer(
      config.endpoint,
      config.apiKey,
      config.bufferSize ?? 50,
      config.flushInterval ?? 10000,
      config.maxRetries ?? 3,
    );

    // Auto-flush on page hide (browser)
    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'hidden') this.buffer.flush();
      });
      window.addEventListener('beforeunload', () => this.buffer.flush());
    }
  }

  startSession(): void { this.sessionId = generateId(); }
  endSession(): void { this.buffer.flush(); this.sessionId = null; }
  setUserId(userId: string): void { this.userId = userId; }

  private log(level: LogLevel, type: LogType, message: string, metadata?: Record<string, unknown>): void {
    const event: LogEvent = {
      timestamp: Date.now(),
      level,
      type,
      message,
      session_id: this.sessionId ?? undefined,
      user_id: this.userId ?? undefined,
      service: this.service,
      environment: this.environment,
      device_type: this.deviceType,
      metadata,
    };
    this.buffer.add(event);
  }

  info(message: string, metadata?: Record<string, unknown>): void { this.log('info', 'custom', message, metadata); }
  warn(message: string, metadata?: Record<string, unknown>): void { this.log('warn', 'custom', message, metadata); }
  error(message: string, metadata?: Record<string, unknown>): void { this.log('error', 'custom', message, metadata); }
  debug(message: string, metadata?: Record<string, unknown>): void { this.log('debug', 'custom', message, metadata); }

  logNavigation(route: string): void { this.log('info', 'navigation', `Navigated to ${route}`); }

  logApiCall(method: string, url: string, status: number, durationMs: number): void {
    const level: LogLevel = status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info';
    this.log(level, 'api_call', `${method} ${url} returned ${status} (${durationMs}ms)`, { method, url, status, duration_ms: durationMs });
  }

  logError(error: Error, metadata?: Record<string, unknown>): void {
    this.log('error', 'crash', error.message, { ...metadata, stack: error.stack, name: error.name });
  }

  async flush(): Promise<void> { await this.buffer.flush(); }
  dispose(): void { this.buffer.dispose(); }
}
