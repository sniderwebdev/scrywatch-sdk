import type { LogEvent } from './types';

export class EventBuffer {
  private buffer: LogEvent[] = [];
  private timer: ReturnType<typeof setTimeout> | null = null;
  private flushing = false;

  constructor(
    private endpoint: string,
    private apiKey: string,
    private bufferSize: number,
    private flushInterval: number,
    private maxRetries: number,
  ) {
    this.startTimer();
  }

  add(event: LogEvent): void {
    this.buffer.push(event);
    if (this.buffer.length >= this.bufferSize) {
      this.flush();
    }
  }

  async flush(): Promise<void> {
    if (this.flushing || this.buffer.length === 0) return;
    this.flushing = true;
    const events = this.buffer.splice(0);

    for (let attempt = 0; attempt <= this.maxRetries; attempt++) {
      try {
        const res = await fetch(`${this.endpoint}/api/ingest`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.apiKey}`,
          },
          body: JSON.stringify({ events }),
        });
        if (res.ok) break;
        if (attempt === this.maxRetries) console.warn('[LogMonitor] Failed to flush events after retries');
      } catch {
        if (attempt === this.maxRetries) console.warn('[LogMonitor] Failed to flush events: network error');
      }
    }

    this.flushing = false;
  }

  private startTimer(): void {
    this.timer = setInterval(() => this.flush(), this.flushInterval);
  }

  dispose(): void {
    if (this.timer) clearInterval(this.timer);
    this.flush();
  }
}
