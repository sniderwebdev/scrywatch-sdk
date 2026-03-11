<?php
declare(strict_types=1);

namespace ScryWatch\Http;

use ScryWatch\ScryWatchException;

/**
 * Internal HTTP client backed by the curl extension.
 * Not PSR-18 compliant — used only when no PSR-18 client is injected.
 *
 * Returns 0 on transport failure (curl_exec === false) so that
 * ScryWatchClient::sendWithRetry() can apply its retry logic uniformly.
 * Only throws ScryWatchException when the curl extension is missing entirely.
 */
final class CurlHttpClient
{
    /**
     * @param string   $url
     * @param string[] $headers  Formatted as "Header-Name: value"
     * @param string   $body     Raw request body
     * @param int      $timeout  Seconds
     *
     * @return int HTTP status code, or 0 on transport failure
     * @throws ScryWatchException if the curl extension is not loaded
     */
    public function post(string $url, array $headers, string $body, int $timeout = 5): int
    {
        if (!extension_loaded('curl')) {
            throw new ScryWatchException(
                'The curl PHP extension is required when no PSR-18 HTTP client is provided.'
            );
        }

        $ch = curl_init($url);

        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_HTTPHEADER     => $headers,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $timeout,
        ]);

        $result   = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        // Return 0 on transport failure; sendWithRetry treats 0 as a retriable error.
        if ($result === false) {
            return 0;
        }

        return (int) $httpCode;
    }
}
