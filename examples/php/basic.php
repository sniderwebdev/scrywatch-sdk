<?php
require __DIR__ . '/../../packages/php/vendor/autoload.php';

use ScryWatch\LogEvent;
use ScryWatch\ScryWatchClient;

$client = new ScryWatchClient(
    endpoint:    'https://api.scrywatch.com',
    apiKey:      getenv('SCRYWATCH_API_KEY') ?: 'YOUR_API_KEY',
    service:     'php-example',
    environment: 'development',
);

$client->setUserId('user-123');
$client->info('Application started');
$client->warn('Cache miss', ['key' => 'user:profile:123', 'ttl_ms' => 0]);
$client->error('Payment failed', ['order_id' => 'ord_789', 'reason' => 'card_declined']);

// Explicit type control
$client->log('info', 'cron', 'Daily report job completed', ['duration_ms' => 4200]);

// Batch send
$client->send([
    new LogEvent(level: 'debug', type: 'custom', message: 'step 1', timestamp: (int)(microtime(true) * 1000)),
    new LogEvent(level: 'debug', type: 'custom', message: 'step 2', timestamp: (int)(microtime(true) * 1000)),
]);

echo "Events sent.\n";
