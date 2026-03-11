<?php
declare(strict_types=1);

namespace ScryWatch\Laravel;

use Monolog\Handler\AbstractProcessingHandler;
use Monolog\Level;
use Monolog\Logger;
use Monolog\LogRecord;
use ScryWatch\ScryWatchClient;

/**
 * Laravel logging channel driver for ScryWatch.
 *
 * Add to config/logging.php channels:
 *
 *   'scrywatch' => [
 *       'driver' => 'custom',
 *       'via'    => \ScryWatch\Laravel\ScryWatchChannel::class,
 *   ],
 *
 * Then use: Log::channel('scrywatch')->info('Something happened');
 */
class ScryWatchChannel
{
    /**
     * @param  array<string,mixed>  $config  Laravel logging channel config array
     *
     * Resolves the ScryWatchClient singleton registered by ScryWatchServiceProvider
     * from the IoC container. Do NOT instantiate ScryWatchClient directly here — that
     * would bypass the endpoint/apiKey/service/environment config.
     */
    public function __invoke(array $config): Logger
    {
        $client  = app(ScryWatchClient::class);
        $handler = new ScryWatchMonologHandler($client);

        return new Logger('scrywatch', [$handler]);
    }
}

/**
 * Monolog handler that forwards log records to ScryWatch.
 *
 * Level mapping:
 *   DEBUG                              → debug
 *   INFO, NOTICE                       → info
 *   WARNING                            → warn
 *   ERROR, CRITICAL, ALERT, EMERGENCY  → error
 */
class ScryWatchMonologHandler extends AbstractProcessingHandler
{
    public function __construct(private readonly ScryWatchClient $client)
    {
        parent::__construct(Level::Debug, bubble: true);
    }

    protected function write(LogRecord $record): void
    {
        $level = match ($record->level) {
            Level::Debug                            => 'debug',
            Level::Info, Level::Notice              => 'info',
            Level::Warning                          => 'warn',
            default                                 => 'error', // Error, Critical, Alert, Emergency
        };

        $this->client->log($level, 'custom', $record->message, $record->context);
    }
}
