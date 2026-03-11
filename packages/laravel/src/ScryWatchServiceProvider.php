<?php
declare(strict_types=1);

namespace ScryWatch\Laravel;

use Illuminate\Support\ServiceProvider;
use ScryWatch\ScryWatchClient;

class ScryWatchServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->mergeConfigFrom(
            __DIR__ . '/../config/scrywatch.php',
            'scrywatch'
        );

        $this->app->singleton(ScryWatchClient::class, function ($app) {
            $config = $app['config']['scrywatch'];

            return new ScryWatchClient(
                endpoint:    $config['endpoint'],
                apiKey:      $config['api_key'] ?? '',
                service:     $config['service'] ?? null,
                environment: $config['environment'] ?? null,
                maxRetries:  (int) ($config['max_retries'] ?? 3),
            );
        });
    }

    public function boot(): void
    {
        if ($this->app->runningInConsole()) {
            $this->publishes([
                __DIR__ . '/../config/scrywatch.php' => config_path('scrywatch.php'),
            ], 'scrywatch-config');
        }
    }
}
