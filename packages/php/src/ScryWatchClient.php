<?php
declare(strict_types=1);

namespace ScryWatch;

use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestFactoryInterface;
use Psr\Http\Message\StreamFactoryInterface;
use ScryWatch\Http\CurlHttpClient;

class ScryWatchClient
{
    private ?string $userId = null;
    private readonly CurlHttpClient $curlClient;

    public function __construct(
        private readonly string                    $endpoint,
        private readonly string                    $apiKey,
        private readonly ?string                   $service        = null,
        private readonly ?string                   $environment    = null,
        private readonly int                       $maxRetries     = 3,
        private readonly ?ClientInterface          $httpClient     = null,
        private readonly ?RequestFactoryInterface  $requestFactory = null,
        private readonly ?StreamFactoryInterface   $streamFactory  = null,
    ) {
        $this->curlClient = new CurlHttpClient();
    }

    public function setUserId(string $id): void
    {
        $this->userId = $id;
    }

    public function info(string $message, array $metadata = []): void
    {
        $this->log('info', 'custom', $message, $metadata);
    }

    public function warn(string $message, array $metadata = []): void
    {
        $this->log('warn', 'custom', $message, $metadata);
    }

    public function error(string $message, array $metadata = []): void
    {
        $this->log('error', 'custom', $message, $metadata);
    }

    public function debug(string $message, array $metadata = []): void
    {
        $this->log('debug', 'custom', $message, $metadata);
    }

    public function log(string $level, string $type, string $message, array $metadata = []): void
    {
        $event = new LogEvent(
            level:       $level,
            type:        $type,
            message:     $message,
            timestamp:   (int) (microtime(true) * 1000),
            userId:      $this->userId,
            environment: $this->environment,
            service:     $this->service,
            metadata:    $metadata ?: null,
        );

        $this->send([$event]);
    }

    /**
     * @param array<LogEvent|array<string,mixed>> $events
     */
    public function send(array $events): void
    {
        $payload = json_encode([
            'events' => array_map(
                static fn($e) => $e instanceof LogEvent ? $e->toArray() : $e,
                $events
            ),
        ], JSON_THROW_ON_ERROR);

        $url     = rtrim($this->endpoint, '/') . '/api/ingest';
        $headers = [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $this->apiKey,
        ];

        $this->sendWithRetry($url, $headers, $payload);
    }

    private function sendWithRetry(string $url, array $headers, string $body): void
    {
        $lastException = null;

        for ($attempt = 0; $attempt <= $this->maxRetries; $attempt++) {
            if ($attempt > 0) {
                usleep($attempt * 500_000);
            }

            try {
                $status = $this->doRequest($url, $headers, $body);
            } catch (\Throwable $e) {
                // PSR-18 ClientException or similar transport error — retriable.
                $lastException = new ScryWatchException(
                    "ScryWatch ingest request failed: {$e->getMessage()}",
                    0,
                    $e
                );
                continue;
            }

            // Only HTTP 202 is the defined success code per the ScryWatch API contract.
            if ($status === 202) {
                return;
            }

            // 4xx = client error; throw immediately without retrying.
            if ($status >= 400 && $status < 500) {
                throw new ScryWatchException(
                    "ScryWatch ingest rejected the request with HTTP {$status}."
                );
            }

            // 0 = transport failure from CurlHttpClient (curl_exec returned false).
            // 5xx = server error. Both are retriable.
            $errorMsg = $status === 0
                ? 'ScryWatch ingest transport failure (curl error).'
                : "ScryWatch ingest returned HTTP {$status}.";

            $lastException = new ScryWatchException($errorMsg);
        }

        throw $lastException ?? new ScryWatchException('ScryWatch ingest failed after retries.');
    }

    private function doRequest(string $url, array $headers, string $body): int
    {
        if ($this->httpClient !== null
            && $this->requestFactory !== null
            && $this->streamFactory !== null
        ) {
            $stream  = $this->streamFactory->createStream($body);
            $request = $this->requestFactory->createRequest('POST', $url)
                ->withBody($stream)
                ->withHeader('Content-Type', 'application/json')
                ->withHeader('Authorization', 'Bearer ' . $this->apiKey);

            $response = $this->httpClient->sendRequest($request);
            return $response->getStatusCode();
        }

        return $this->curlClient->post($url, $headers, $body);
    }
}
