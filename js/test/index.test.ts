import { describe, it, expect, vi, beforeEach } from 'vitest';
import { LogMonitor } from '../src/index';
import { MemoryStorage } from './support/memoryStorage';

describe('LogMonitor', () => {
  let fetchMock: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchMock = vi.fn().mockResolvedValue({ ok: true });
    (globalThis as { fetch?: typeof fetch }).fetch = fetchMock as unknown as typeof fetch;
    (globalThis as { localStorage?: Storage }).localStorage = new MemoryStorage();
  });

  it('generates a device id on first init and reuses the persisted one on the next init', () => {
    const monitor1 = new LogMonitor({ endpoint: 'https://api.example.com', apiKey: 'k', flushInterval: 999999 });
    const id1 = monitor1.getDeviceId();
    monitor1.dispose();

    const monitor2 = new LogMonitor({ endpoint: 'https://api.example.com', apiKey: 'k', flushInterval: 999999 });
    const id2 = monitor2.getDeviceId();
    monitor2.dispose();

    expect(id1).toBe(id2);
  });

  it('identify() sets the user id and posts { user_id, traits } to /api/identify with the Bearer key', async () => {
    const monitor = new LogMonitor({ endpoint: 'https://api.example.com', apiKey: 'k', flushInterval: 999999 });

    monitor.identify('user-42', { email: 'x@y.com' });
    // identify is fire-and-forget; flush the microtask queue for the internal promise.
    await new Promise(resolve => setTimeout(resolve, 0));

    const identifyCall = fetchMock.mock.calls.find(([url]) => String(url).endsWith('/api/identify'));
    expect(identifyCall).toBeTruthy();
    const [, init] = identifyCall!;
    expect(init.headers.Authorization).toBe('Bearer k');
    expect(JSON.parse(init.body)).toEqual({ user_id: 'user-42', traits: { email: 'x@y.com' } });

    // subsequent events should now carry the identified user_id.
    monitor.info('after identify');
    await monitor.flush();

    const ingestCall = fetchMock.mock.calls.find(([url]) => String(url).endsWith('/api/ingest'));
    expect(ingestCall).toBeTruthy();
    const body = JSON.parse(ingestCall![1].body);
    expect(body.events[0].user_id).toBe('user-42');

    monitor.dispose();
  });

  it('identify() never throws to the caller even when the network call rejects', async () => {
    fetchMock.mockRejectedValue(new Error('offline'));
    const monitor = new LogMonitor({ endpoint: 'https://api.example.com', apiKey: 'k', flushInterval: 999999 });

    expect(() => monitor.identify('user-1')).not.toThrow();
    await new Promise(resolve => setTimeout(resolve, 0));

    monitor.dispose();
  });
});
