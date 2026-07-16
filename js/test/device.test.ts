import { describe, it, expect, beforeEach } from 'vitest';
import { getOrCreateDeviceId } from '../src/device';
import { MemoryStorage } from './support/memoryStorage';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

describe('getOrCreateDeviceId', () => {
  beforeEach(() => {
    delete (globalThis as { localStorage?: Storage }).localStorage;
  });

  it('generates and persists a UUID device id on first use', () => {
    const storage = new MemoryStorage();
    (globalThis as { localStorage?: Storage }).localStorage = storage;

    const id = getOrCreateDeviceId();

    expect(id).toMatch(UUID_RE);
    expect(storage.getItem('scrywatch_device_id')).toBe(id);
  });

  it('reuses the persisted id on the next call/init instead of generating a new one', () => {
    const storage = new MemoryStorage();
    (globalThis as { localStorage?: Storage }).localStorage = storage;

    const first = getOrCreateDeviceId();
    const second = getOrCreateDeviceId();

    expect(second).toBe(first);
    expect(storage.getItem('scrywatch_device_id')).toBe(first);
  });

  it('loads an id that was already persisted by a previous session', () => {
    const storage = new MemoryStorage();
    storage.setItem('scrywatch_device_id', 'pre-existing-id');
    (globalThis as { localStorage?: Storage }).localStorage = storage;

    expect(getOrCreateDeviceId()).toBe('pre-existing-id');
  });

  it('falls back to an in-memory id (never throws) when localStorage is unavailable', () => {
    expect((globalThis as { localStorage?: Storage }).localStorage).toBeUndefined();

    let id = '';
    expect(() => {
      id = getOrCreateDeviceId();
    }).not.toThrow();
    expect(id).toMatch(UUID_RE);
  });

  it('falls back to an in-memory id (never throws) when localStorage access throws', () => {
    (globalThis as { localStorage?: Storage }).localStorage = {
      getItem() {
        throw new Error('access blocked');
      },
      setItem() {
        throw new Error('access blocked');
      },
    } as unknown as Storage;

    expect(() => getOrCreateDeviceId()).not.toThrow();
  });
});
