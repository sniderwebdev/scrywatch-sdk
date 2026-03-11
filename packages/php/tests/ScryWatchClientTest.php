<?php
declare(strict_types=1);

namespace ScryWatch\Tests;

use Nyholm\Psr7\Factory\Psr17Factory;
use Nyholm\Psr7\Response;
use PHPUnit\Framework\TestCase;
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\RequestInterface;
use ScryWatch\ScryWatchClient;
use ScryWatch\ScryWatchException;

class ScryWatchClientTest extends TestCase
{
    private Psr17Factory $factory;

    protected function setUp(): void
    {
        $this->factory = new Psr17Factory();
    }

    private function makeClient(int $statusCode = 202, ?callable $assert = null): ScryWatchClient
    {
        $httpClient = $this->createMock(ClientInterface::class);
        $response   = new Response($statusCode);

        $expectation = $httpClient->expects($this->atLeastOnce())
            ->method('sendRequest');

        if ($assert !== null) {
            $expectation->with($this->callback($assert));
        }

        $expectation->willReturn($response);

        return new ScryWatchClient(
            endpoint:       'https://api.example.com',
            apiKey:         'test-key',
            maxRetries:     0,
            httpClient:     $httpClient,
            requestFactory: $this->factory,
            streamFactory:  $this->factory,
        );
    }

    public function test_info_sends_without_error(): void
    {
        $client = $this->makeClient(202);
        $client->info('Hello world');
        $this->assertTrue(true); // no exception = pass
    }

    public function test_request_uses_correct_endpoint_and_auth(): void
    {
        $client = $this->makeClient(202, function (RequestInterface $req): bool {
            $this->assertSame('POST', $req->getMethod());
            $this->assertStringEndsWith('/api/ingest', (string) $req->getUri());
            $this->assertSame('Bearer test-key', $req->getHeaderLine('Authorization'));
            $this->assertSame('application/json', $req->getHeaderLine('Content-Type'));
            return true;
        });

        $client->info('test');
    }

    public function test_request_body_has_events_envelope(): void
    {
        $client = $this->makeClient(202, function (RequestInterface $req): bool {
            $body = json_decode((string) $req->getBody(), true);
            $this->assertArrayHasKey('events', $body);
            $this->assertCount(1, $body['events']);
            $this->assertSame('info', $body['events'][0]['level']);
            $this->assertSame('custom', $body['events'][0]['type']);
            $this->assertSame('envelope test', $body['events'][0]['message']);
            return true;
        });

        $client->info('envelope test');
    }

    public function test_4xx_throws_immediately_without_retry(): void
    {
        $httpClient = $this->createMock(ClientInterface::class);
        $httpClient->expects($this->once()) // exactly once — no retry
            ->method('sendRequest')
            ->willReturn(new Response(400));

        $client = new ScryWatchClient(
            endpoint:       'https://api.example.com',
            apiKey:         'key',
            maxRetries:     3,
            httpClient:     $httpClient,
            requestFactory: $this->factory,
            streamFactory:  $this->factory,
        );

        $this->expectException(ScryWatchException::class);
        $client->info('bad event');
    }

    public function test_5xx_retries_up_to_max_retries(): void
    {
        $httpClient = $this->createMock(ClientInterface::class);
        $httpClient->expects($this->exactly(3)) // initial + 2 retries
            ->method('sendRequest')
            ->willReturn(new Response(503));

        $client = new ScryWatchClient(
            endpoint:       'https://api.example.com',
            apiKey:         'key',
            maxRetries:     2,
            httpClient:     $httpClient,
            requestFactory: $this->factory,
            streamFactory:  $this->factory,
        );

        $this->expectException(ScryWatchException::class);
        $client->info('server error');
    }

    public function test_setUserId_attaches_to_events(): void
    {
        $client = $this->makeClient(202, function (RequestInterface $req): bool {
            $body = json_decode((string) $req->getBody(), true);
            $this->assertSame('user-42', $body['events'][0]['user_id']);
            return true;
        });

        $client->setUserId('user-42');
        $client->info('with user');
    }

    public function test_warn_error_debug_use_correct_levels(): void
    {
        foreach (['warn', 'error', 'debug'] as $level) {
            $client = $this->makeClient(202, function (RequestInterface $req) use ($level): bool {
                $body = json_decode((string) $req->getBody(), true);
                $this->assertSame($level, $body['events'][0]['level']);
                return true;
            });
            $client->$level("{$level} message");
        }
    }
}
