<?php

declare(strict_types=1);

namespace App;

use Dotenv\Dotenv;

final class Config
{
    private static ?self $instance = null;

    public readonly string $dbHost;
    public readonly int $dbPort;
    public readonly string $dbUser;
    public readonly string $dbPass;
    public readonly string $dbName;
    public readonly string $ruteoDb;

    public readonly string $ftpHost;
    public readonly string $ftpUser;
    public readonly string $ftpPass;
    public readonly string $ftpRoot;
    public readonly int $ftpPool;

    public readonly string $jwtSecret;
    public readonly int $accessTtlSeconds;
    public readonly int $refreshTtlSeconds;

    public readonly string $cacheDir;
    public readonly int $piezasDiasDefault;

    // Reglas del negocio (iguales a config.js del api/ Node)
    public readonly int $recorridoAbierto; // ruteo.grupo_asignacion.estado: solo 0 (abierto) se consulta
    public readonly int $estadoEnDistribucion; // flash_piezas_estados_variables.id "En distribucion"
    public readonly int $segundosSinSenal; // pasado este tiempo sin puntos GPS, "sin señal reciente"
    public readonly int $groupCliente; // users_groups.group_id = Cliente
    public readonly int $clienteActivo; // flash_clientes_estados: 1 Activo, 2 Inactivo, 3 Suspendido
    public readonly int $estadoDefinitivo; // pieza_estado_id que marca estado definitivo (tarjeta azul)

    private function __construct()
    {
        $root = dirname(__DIR__);
        if (is_file($root . '/.env')) {
            Dotenv::createImmutable($root)->load();
        }

        $req = static function (string $k): string {
            $v = $_ENV[$k] ?? getenv($k);
            if ($v === false || $v === null || $v === '') {
                throw new \RuntimeException("Falta la variable de entorno {$k}");
            }
            return (string) $v;
        };
        $opt = static fn (string $k, string $default): string => (string) (($_ENV[$k] ?? getenv($k)) ?: $default);

        $this->dbHost = $req('DB_HOST');
        $this->dbPort = (int) $opt('DB_PORT', '3306');
        $this->dbUser = $req('DB_USER');
        $this->dbPass = $req('DB_PASS');
        $this->dbName = $opt('DB_NAME', 'intran23_mis_envios');
        $this->ruteoDb = $opt('RUTEO_DB', 'intran23_ruteo');

        $this->ftpHost = $req('FTP_HOST');
        $this->ftpUser = $req('FTP_USER');
        $this->ftpPass = $req('FTP_PASS');
        $this->ftpRoot = $opt('FTP_ROOT', '/archivoscompartidos.intranetflash.com/public');
        $this->ftpPool = (int) $opt('FTP_POOL', '3');

        $this->jwtSecret = $req('JWT_SECRET');
        $this->accessTtlSeconds = (int) $opt('ACCESS_TTL', '1800');
        $this->refreshTtlSeconds = (int) $opt('REFRESH_TTL', '34560000');

        $this->cacheDir = $opt('CACHE_DIR', dirname(__DIR__) . '/cache');
        $this->piezasDiasDefault = (int) $opt('PIEZAS_DIAS', '30');

        $this->recorridoAbierto = 0;
        $this->estadoEnDistribucion = 2;
        $this->segundosSinSenal = 15 * 60;
        $this->groupCliente = 4;
        $this->clienteActivo = 1;
        $this->estadoDefinitivo = 2;
    }

    public static function get(): self
    {
        return self::$instance ??= new self();
    }
}
