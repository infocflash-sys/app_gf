<?php

declare(strict_types=1);

namespace App;

final class Files
{
    // Carpetas de imágenes: las recientes están en "acuses"; el resto son históricas.
    private const IMAGE_FOLDERS = [
        'acuses', 'acuses2', 'acuses4', 'acuses5', 'acuses6', 'acuses_sispoapp', 'eventos', 'ago-sep-24', 'oct-24',
    ];
    private const SIZES = ['thumb' => 360, 'full' => 1280];

    private static function cacheDir(): string
    {
        $dir = Config::get()->cacheDir;
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        return $dir;
    }

    private static function cachePath(string $key, string $ext): string
    {
        return self::cacheDir() . '/' . sha1($key) . $ext;
    }

    private static function locateFile(string $key): string
    {
        return self::cacheDir() . '/where/' . sha1($key) . '.json';
    }

    /** Carpeta donde está la imagen (con caché de "no encontrada" por 10 min), o null. */
    private static function locateImage(string $name): ?string
    {
        $c = Config::get();
        $locFile = self::locateFile($name);
        if (is_file($locFile)) {
            $data = json_decode((string) file_get_contents($locFile), true);
            if (is_array($data) && ($data['folder'] !== null || ($data['until'] ?? 0) > time())) {
                return $data['folder'];
            }
        }
        foreach (self::IMAGE_FOLDERS as $f) {
            if (Ftp::size("{$c->ftpRoot}/imagenes/{$f}/{$name}") !== null) {
                self::rememberFolder($locFile, $f);
                return $f;
            }
        }
        self::rememberFolder($locFile, null, time() + 10 * 60);
        return null;
    }

    private static function rememberFolder(string $locFile, ?string $folder, ?int $until = null): void
    {
        $dir = dirname($locFile);
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        file_put_contents($locFile, json_encode(['folder' => $folder, 'until' => $until]));
    }

    private static function resize(string $rawPath, string $destPath, int $width): void
    {
        $info = @getimagesize($rawPath);
        if ($info === false) {
            throw new \RuntimeException('Imagen inválida.');
        }
        $src = match ($info[2]) {
            IMAGETYPE_JPEG => imagecreatefromjpeg($rawPath),
            IMAGETYPE_PNG => imagecreatefrompng($rawPath),
            default => throw new \RuntimeException('Formato de imagen no soportado.'),
        };
        if ($src === false) {
            throw new \RuntimeException('No se pudo leer la imagen.');
        }

        // Rotar según EXIF (las fotos de acuse vienen de celulares)
        if (function_exists('exif_read_data') && $info[2] === IMAGETYPE_JPEG) {
            $exif = @exif_read_data($rawPath);
            $orientation = $exif['Orientation'] ?? 1;
            $src = match ($orientation) {
                3 => imagerotate($src, 180, 0),
                6 => imagerotate($src, -90, 0),
                8 => imagerotate($src, 90, 0),
                default => $src,
            };
        }

        $srcW = imagesx($src);
        $srcH = imagesy($src);
        $w = min($width, $srcW); // withoutEnlargement: nunca agranda
        $h = (int) round($srcH * ($w / $srcW));

        $dst = imagecreatetruecolor($w, $h);
        imagecopyresampled($dst, $src, 0, 0, 0, 0, $w, $h, $srcW, $srcH);
        imagejpeg($dst, $destPath, 76);
        imagedestroy($src);
        imagedestroy($dst);
    }

    /** Imagen reducida y cacheada en disco. Devuelve ['file' => ..., 'mime' => ...] o null si no existe. */
    public static function getImage(string $name, string $size = 'thumb'): ?array
    {
        $width = self::SIZES[$size] ?? self::SIZES['thumb'];
        $out = self::cachePath("img:{$name}:{$width}", '.jpg');
        if (!is_file($out)) {
            $lock = fopen($out . '.lock', 'c');
            flock($lock, LOCK_EX);
            try {
                if (!is_file($out)) {
                    $folder = self::locateImage($name);
                    if ($folder !== null) {
                        $c = Config::get();
                        $raw = self::cachePath("raw:{$name}", '.bin');
                        try {
                            Ftp::download("{$c->ftpRoot}/imagenes/{$folder}/{$name}", $raw);
                            // con una sola descarga se generan todos los tamaños
                            foreach (self::SIZES as $w) {
                                $dest = self::cachePath("img:{$name}:{$w}", '.jpg');
                                self::resize($raw, $dest, $w);
                            }
                        } finally {
                            @unlink($raw);
                        }
                    }
                }
            } finally {
                flock($lock, LOCK_UN);
                fclose($lock);
            }
        }
        return is_file($out) ? ['file' => $out, 'mime' => 'image/jpeg'] : null;
    }

    /** PDF cacheado en disco. Devuelve ['file' => ..., 'mime' => ...] o null si no existe. */
    public static function getPdf(string $name): ?array
    {
        $out = self::cachePath("pdf:{$name}", '.pdf');
        if (!is_file($out)) {
            $lock = fopen($out . '.lock', 'c');
            flock($lock, LOCK_EX);
            try {
                if (!is_file($out)) {
                    $c = Config::get();
                    $remote = "{$c->ftpRoot}/archivos/documentacion/{$name}";
                    if (Ftp::size($remote) !== null) {
                        $tmp = $out . '.part';
                        Ftp::download($remote, $tmp);
                        rename($tmp, $out);
                    }
                }
            } finally {
                flock($lock, LOCK_UN);
                fclose($lock);
            }
        }
        return is_file($out) ? ['file' => $out, 'mime' => 'application/pdf'] : null;
    }
}
