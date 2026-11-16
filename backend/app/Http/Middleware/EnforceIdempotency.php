<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

/**
 * Makes retried creating requests safe. When a client sends an `Idempotency-Key`
 * header, the first successful response for that user and key is stored for 24
 * hours and replayed for equivalent retries instead of creating a duplicate.
 * Reusing a key with a different method, path or payload is rejected, and a
 * concurrent duplicate while the first request is still running gets 409.
 * Requests without the header behave exactly as before. Failed (non-2xx)
 * responses are not stored, so a corrected retry can reuse the key.
 */
class EnforceIdempotency
{
    private const TTL_SECONDS = 86400;

    public function handle(Request $request, Closure $next): Response
    {
        $key = $request->header('Idempotency-Key');
        $user = $request->user();

        if ($key === null || $user === null) {
            return $next($request);
        }

        if (preg_match('/^[A-Za-z0-9._:-]{8,128}$/', $key) !== 1) {
            return $this->error(422, 'invalid_idempotency_key', 'The Idempotency-Key must be 8-128 characters of letters, digits and . _ : -.');
        }

        $cacheKey = 'idempotency:'.$user->getKey().':'.hash('sha256', $key);
        $fingerprint = $this->fingerprint($request);
        $stored = Cache::get($cacheKey);

        if (is_array($stored)) {
            return $this->replay($stored, $fingerprint);
        }

        $lock = Cache::lock($cacheKey.':lock', 30);
        if (! $lock->get()) {
            return $this->error(409, 'idempotency_in_progress', 'A request with this Idempotency-Key is still being processed.');
        }

        try {
            $stored = Cache::get($cacheKey);
            if (is_array($stored)) {
                return $this->replay($stored, $fingerprint);
            }

            $response = $next($request);

            if ($response->isSuccessful() && $response instanceof JsonResponse) {
                Cache::put($cacheKey, [
                    'fingerprint' => $fingerprint,
                    'status' => $response->getStatusCode(),
                    'body' => $response->getContent(),
                ], self::TTL_SECONDS);
            }

            return $response;
        } finally {
            $lock->release();
        }
    }

    /**
     * @param  array{fingerprint: string, status: int, body: string}  $stored
     */
    private function replay(array $stored, string $fingerprint): Response
    {
        if (! hash_equals($stored['fingerprint'], $fingerprint)) {
            return $this->error(422, 'idempotency_key_reused', 'This Idempotency-Key was already used with a different request.');
        }

        return JsonResponse::fromJsonString($stored['body'], $stored['status'], ['Idempotent-Replayed' => 'true']);
    }

    private function fingerprint(Request $request): string
    {
        $files = [];
        foreach ($request->allFiles() as $name => $file) {
            foreach ((array) $file as $upload) {
                $files[$name][] = $upload instanceof UploadedFile && $upload->getRealPath() !== false
                    ? hash_file('sha256', $upload->getRealPath())
                    : '';
            }
        }

        return hash('sha256', json_encode([
            $request->method(),
            $request->path(),
            $request->all(),
            $files,
        ], JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE));
    }

    private function error(int $status, string $code, string $message): JsonResponse
    {
        return response()->json(['error' => ['code' => $code, 'message' => $message]], $status);
    }
}
