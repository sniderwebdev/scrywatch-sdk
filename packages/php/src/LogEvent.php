<?php
declare(strict_types=1);

namespace ScryWatch;

final class LogEvent
{
    public function __construct(
        public readonly string  $level,
        public readonly string  $type,
        public readonly string  $message,
        public readonly int     $timestamp,
        public readonly ?string $userId      = null,
        public readonly ?string $sessionId   = null,
        public readonly ?string $environment = null,
        public readonly ?string $service     = null,
        public readonly ?string $deviceType  = null,
        public readonly ?string $traceId     = null,
        public readonly ?string $spanId      = null,
        public readonly ?array  $metadata    = null,
    ) {}

    public function toArray(): array
    {
        $data = [
            'level'     => $this->level,
            'type'      => $this->type,
            'message'   => $this->message,
            'timestamp' => $this->timestamp,
        ];

        if ($this->userId      !== null) $data['user_id']     = $this->userId;
        if ($this->sessionId   !== null) $data['session_id']  = $this->sessionId;
        if ($this->environment !== null) $data['environment'] = $this->environment;
        if ($this->service     !== null) $data['service']     = $this->service;
        if ($this->deviceType  !== null) $data['device_type'] = $this->deviceType;
        if ($this->traceId     !== null) $data['trace_id']    = $this->traceId;
        if ($this->spanId      !== null) $data['span_id']     = $this->spanId;
        if ($this->metadata    !== null) $data['metadata']    = $this->metadata;

        return $data;
    }
}
