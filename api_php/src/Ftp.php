<?php

declare(strict_types=1);

namespace App;

/**
 * Cliente FTP al hosting del ERP (archivoscompartidos.intranetflash.com), donde viven las fotos
 * de acuse y los PDF. A diferencia del api/ en Node (que mantiene un pool de conexiones persistente
 * entre requests), acá cada request de PHP-FPM es un proceso aparte: se abre una conexión por
 * request (reusada para todas las llamadas de esa request) y se cierra sola al terminar.
 */
final class Ftp
{
    private static mixed $conn = null;

    private static function connection(): mixed
    {
        if (self::$conn !== null) {
            return self::$conn;
        }
        $c = Config::get();
        $conn = ftp_connect($c->ftpHost, 21, 15);
        if ($conn === false) {
            throw new \RuntimeException('No se pudo conectar al FTP.');
        }
        if (!ftp_login($conn, $c->ftpUser, $c->ftpPass)) {
            ftp_close($conn);
            throw new \RuntimeException('Login FTP rechazado.');
        }
        ftp_pasv($conn, true);
        self::$conn = $conn;
        return $conn;
    }

    /** Tamaño en bytes, o null si el archivo no existe. */
    public static function size(string $path): ?int
    {
        $size = ftp_size(self::connection(), $path);
        return $size >= 0 ? $size : null;
    }

    /** Descarga a un archivo local. Lanza excepción si falla (no distingue "no existe": usar size() antes). */
    public static function download(string $remotePath, string $localPath): void
    {
        if (!ftp_get(self::connection(), $localPath, $remotePath, FTP_BINARY)) {
            throw new \RuntimeException("No se pudo descargar {$remotePath} por FTP.");
        }
    }

    public static function close(): void
    {
        if (self::$conn !== null) {
            @ftp_close(self::$conn);
            self::$conn = null;
        }
    }
}
