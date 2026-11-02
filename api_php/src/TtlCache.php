<?php

declare(strict_types=1);

namespace App;

/**
 * Caché con TTL persistida en disco (no hay proceso persistente como en Node: cada request de
 * PHP-FPM es independiente). Usa flock() para que, si varios requests piden lo mismo a la vez,
 * solo uno llame al loader() y los demás esperen y lean el resultado ya cacheado.
 */
final class TtlCache
{
    public function __construct(private readonly string $dir)
    {
        if (!is_dir($this->dir)) {
            mkdir($this->dir, 0775, true);
        }
    }

    private function fileFor(string $key): string
    {
        return $this->dir . '/' . sha1($key) . '.cache';
    }

    private function lockFileFor(string $key): string
    {
        return $this->dir . '/' . sha1($key) . '.lock';
    }

    /** @return array{exp:int,v:mixed}|null */
    private function read(string $file): ?array
    {
        $raw = @file_get_contents($file);
        if ($raw === false) {
            return null;
        }
        $data = @unserialize($raw, ['allowed_classes' => false]);
        if (!is_array($data) || !isset($data['exp'], $data['v'])) {
            return null;
        }
        if ($data['exp'] <= time()) {
            return null;
        }
        return $data;
    }

    private function write(string $file, mixed $v, int $ttlSeconds): void
    {
        $tmp = $file . '.' . getmypid() . '.tmp';
        file_put_contents($tmp, serialize(['exp' => time() + $ttlSeconds, 'v' => $v]));
        rename($tmp, $file);
    }

    /** Devuelve el valor en caché o lo carga una sola vez aunque lo pidan varios a la vez. */
    public function get(string $key, int $ttlSeconds, callable $loader): mixed
    {
        $file = $this->fileFor($key);
        $hit = $this->read($file);
        if ($hit !== null) {
            return $hit['v'];
        }

        $lockFile = $this->lockFileFor($key);
        $fp = fopen($lockFile, 'c');
        if ($fp === false) {
            // sin filesystem para el lock, se ejecuta igual sin dedupe entre procesos
            return $loader();
        }
        try {
            flock($fp, LOCK_EX);
            // puede que otro proceso ya lo haya resuelto mientras esperábamos el lock
            $hit = $this->read($file);
            if ($hit !== null) {
                return $hit['v'];
            }
            $v = $loader();
            $this->write($file, $v, $ttlSeconds);
            return $v;
        } finally {
            flock($fp, LOCK_UN);
            fclose($fp);
        }
    }

    public function delete(string $key): void
    {
        @unlink($this->fileFor($key));
    }
}
