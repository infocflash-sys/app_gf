<?php

declare(strict_types=1);

namespace App;

/** Límite de pedidos por IP y ventana de tiempo, persistido en disco (equivalente a @fastify/rate-limit). */
final class RateLimit
{
    private static function dir(): string
    {
        $dir = Config::get()->cacheDir . '/ratelimit';
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        return $dir;
    }

    private static function clientIp(): string
    {
        return $_SERVER['REMOTE_ADDR'] ?? 'desconocida';
    }

    /** true si la request puede pasar; false si superó el máximo para esa clave+ventana. */
    public static function allow(string $bucket, int $max, int $windowSeconds): bool
    {
        $windowId = intdiv(time(), $windowSeconds);
        $key = sha1($bucket . ':' . self::clientIp() . ':' . $windowId);
        $file = self::dir() . '/' . $key . '.cnt';
        $fp = fopen($file, 'c+');
        if ($fp === false) {
            return true; // sin filesystem, no bloqueamos
        }
        try {
            flock($fp, LOCK_EX);
            $raw = stream_get_contents($fp);
            $n = ((int) $raw) + 1;
            ftruncate($fp, 0);
            rewind($fp);
            fwrite($fp, (string) $n);
            return $n <= $max;
        } finally {
            flock($fp, LOCK_UN);
            fclose($fp);
        }
    }
}
