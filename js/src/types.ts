export type LogLevel = 'error' | 'warn' | 'info' | 'debug';
export type LogType = 'crash' | 'session' | 'navigation' | 'api_call' | 'custom';

export interface LogEvent {
  timestamp: number;
  level: LogLevel;
  type: LogType;
  message: string;
  user_id?: string;
  session_id?: string;
  environment?: string;
  service?: string;
  device_type?: string;
  metadata?: Record<string, unknown>;
}

export interface LogMonitorConfig {
  endpoint: string;
  apiKey: string;
  service?: string;
  environment?: string;
  flushInterval?: number;   // ms, default 10000
  bufferSize?: number;      // default 50
  maxRetries?: number;      // default 3
}
