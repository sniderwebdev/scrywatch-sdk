<?php
declare(strict_types=1);

namespace ScryWatch\Tests;

use PHPUnit\Framework\TestCase;
use ScryWatch\LogEvent;

class LogEventTest extends TestCase
{
    public function test_toArray_includes_required_fields(): void
    {
        $event = new LogEvent(
            level: 'error',
            type: 'custom',
            message: 'Something broke',
            timestamp: 1741200000000,
        );

        $data = $event->toArray();

        $this->assertSame('error', $data['level']);
        $this->assertSame('custom', $data['type']);
        $this->assertSame('Something broke', $data['message']);
        $this->assertSame(1741200000000, $data['timestamp']);
    }

    public function test_toArray_omits_null_optional_fields(): void
    {
        $event = new LogEvent(level: 'info', type: 'custom', message: 'hi', timestamp: 1000);
        $data  = $event->toArray();

        $this->assertArrayNotHasKey('user_id', $data);
        $this->assertArrayNotHasKey('session_id', $data);
        $this->assertArrayNotHasKey('environment', $data);
        $this->assertArrayNotHasKey('service', $data);
        $this->assertArrayNotHasKey('device_type', $data);
        $this->assertArrayNotHasKey('trace_id', $data);
        $this->assertArrayNotHasKey('span_id', $data);
        $this->assertArrayNotHasKey('metadata', $data);
    }

    public function test_toArray_includes_optional_fields_when_set(): void
    {
        $event = new LogEvent(
            level: 'warn',
            type: 'api_call',
            message: 'slow request',
            timestamp: 2000,
            userId: 'u1',
            sessionId: 's1',
            environment: 'production',
            service: 'api',
            deviceType: 'desktop',
            traceId: 'abc',
            spanId: 'def',
            metadata: ['latency_ms' => 1200],
        );

        $data = $event->toArray();

        $this->assertSame('u1', $data['user_id']);
        $this->assertSame('s1', $data['session_id']);
        $this->assertSame('production', $data['environment']);
        $this->assertSame('api', $data['service']);
        $this->assertSame('desktop', $data['device_type']);
        $this->assertSame('abc', $data['trace_id']);
        $this->assertSame('def', $data['span_id']);
        $this->assertSame(['latency_ms' => 1200], $data['metadata']);
    }
}
