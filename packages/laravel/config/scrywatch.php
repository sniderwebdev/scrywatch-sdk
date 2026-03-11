<?php

return [
    /*
    |--------------------------------------------------------------------------
    | ScryWatch Endpoint
    |--------------------------------------------------------------------------
    | The base URL for the ScryWatch ingest API.
    */
    'endpoint' => env('SCRYWATCH_ENDPOINT', 'https://api.scrywatch.com'),

    /*
    |--------------------------------------------------------------------------
    | API Key
    |--------------------------------------------------------------------------
    | Your ScryWatch project API key. Set SCRYWATCH_API_KEY in your .env file.
    */
    'api_key' => env('SCRYWATCH_API_KEY'),

    /*
    |--------------------------------------------------------------------------
    | Service Name
    |--------------------------------------------------------------------------
    | Tags every log event with this service name. Defaults to APP_NAME.
    */
    'service' => env('SCRYWATCH_SERVICE', env('APP_NAME', 'laravel')),

    /*
    |--------------------------------------------------------------------------
    | Environment
    |--------------------------------------------------------------------------
    | Tags every log event with this environment label. Defaults to APP_ENV.
    */
    'environment' => env('SCRYWATCH_ENV', env('APP_ENV', 'production')),

    /*
    |--------------------------------------------------------------------------
    | Max Retries
    |--------------------------------------------------------------------------
    | How many times to retry ingest on network error or 5xx response.
    */
    'max_retries' => (int) env('SCRYWATCH_MAX_RETRIES', 3),
];
