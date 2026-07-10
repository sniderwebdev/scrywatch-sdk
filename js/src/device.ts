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
