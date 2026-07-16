const DEVICE_ID_STORAGE_KEY = 'scrywatch_device_id';

let inMemoryDeviceId: string | null = null;

function generateUuid(): string {
  const cryptoObj = (globalThis as { crypto?: Crypto }).crypto;
  if (cryptoObj && typeof cryptoObj.randomUUID === 'function') {
    return cryptoObj.randomUUID();
  }
  const bytes = new Uint8Array(16);
  if (cryptoObj && typeof cryptoObj.getRandomValues === 'function') {
    cryptoObj.getRandomValues(bytes);
  } else {
    for (let i = 0; i < bytes.length; i++) bytes[i] = Math.floor(Math.random() * 256);
  }
  // Set version (4) and variant (RFC 4122) bits.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes).map(b => b.toString(16).padStart(2, '0'));
  return `${hex.slice(0, 4).join('')}-${hex.slice(4, 6).join('')}-${hex.slice(6, 8).join('')}-${hex.slice(8, 10).join('')}-${hex.slice(10, 16).join('')}`;
}

/**
 * Loads the persisted anonymous device id from localStorage, generating and
 * persisting a new one on first use. Falls back to an in-memory id (not
 * persisted across reloads) in non-browser environments or when localStorage
 * is unavailable/blocked — never throws.
 */
export function getOrCreateDeviceId(): string {
  try {
    const storage = (globalThis as { localStorage?: Storage }).localStorage;
    if (storage) {
      const existing = storage.getItem(DEVICE_ID_STORAGE_KEY);
      if (existing) return existing;
      const generated = generateUuid();
      storage.setItem(DEVICE_ID_STORAGE_KEY, generated);
      return generated;
    }
  } catch {
    // localStorage inaccessible (SSR, privacy mode, disabled) — fall through.
  }
  if (!inMemoryDeviceId) inMemoryDeviceId = generateUuid();
  return inMemoryDeviceId;
}

export function detectDeviceType(): string {
  if (typeof navigator !== 'undefined') {
    const ua = navigator.userAgent.toLowerCase();
    if (/iphone|ipad|ipod/.test(ua)) return 'ios';
    if (/android/.test(ua)) return 'android';
    if (/tablet/.test(ua)) return 'tablet';
    if (/mobile/.test(ua)) return 'mobile';
    return 'desktop';
  }
  const proc = (globalThis as { process?: { platform?: string } }).process;
  if (proc && typeof proc.platform === 'string') {
    const platform = proc.platform;
    if (platform === 'darwin') return 'macos';
    if (platform === 'win32') return 'windows';
    if (platform === 'linux') return 'linux';
    return platform;
  }
  return 'unknown';
}
