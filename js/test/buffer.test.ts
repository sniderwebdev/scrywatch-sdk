import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EventBuffer } from '../src/buffer';
import type { LogEvent } from '../src/types';

function makeEvent(): LogEvent {
  return { timestamp: Date.now(), level: 'info', type: 'custom', message: 'hi' };
}

describe('EventBuffer', () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn().mockResolvedValue({ ok: true });
    (globalThis as { fetch?: typeof fetch }).fetch = fetchMock as unknown as typeof fetch;
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('includes device_id as a top-level field on the ingest payload (not per-event)', async () => {
    const buffer = new EventBuffer('https://api.example.com', 'key123', 50, 999999, 3, 'device-abc');
    buffer.add(makeEvent());
    await buffer.flush();
    buffer.dispose();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://api.example.com/api/ingest');

    const body = JSON.parse(init.body);
    expect(body.device_id).toBe('device-abc');
    expect(body.events).toHaveLength(1);
    expect(body.events[0].device_id).toBeUndefined();
  });

  it('identify() posts to /api/identify with the Bearer auth header and { user_id, traits } body', async () => {
    const buffer = new EventBuffer('https://api.example.com', 'key123', 50, 999999, 3, 'device-abc');
    await buffer.identify('user-1', { email: 'a@b.com' });
    buffer.dispose();

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://api.example.com/api/identify');
    expect(init.method).toBe('POST');
    expect(init.headers.Authorization).toBe('Bearer key123');
    expect(init.headers['Content-Type']).toBe('application/json');
    expect(JSON.parse(init.body)).toEqual({ user_id: 'user-1', traits: { email: 'a@b.com' } });
  });

  it('identify() swallows network errors instead of throwing/rejecting', async () => {
    fetchMock.mockRejectedValue(new Error('network down'));
    const buffer = new EventBuffer('https://api.example.com', 'key123', 50, 999999, 3, 'device-abc');

    await expect(buffer.identify('user-1')).resolves.toBeUndefined();
    buffer.dispose();
  });
});
