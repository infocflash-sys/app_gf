<?php

declare(strict_types=1);

namespace App;

use PDO;

final class Db
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo !== null) {
            return self::$pdo;
        }
        $c = Config::get();
        $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $c->dbHost, $c->dbPort, $c->dbName);
        self::$pdo = new PDO($dsn, $c->dbUser, $c->dbPass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => true,
            PDO::ATTR_TIMEOUT => 15,
        ]);
        return self::$pdo;
    }

    /**
     * Ejecuta una consulta con placeholders "?". Un parámetro que sea array se expande a
     * "?,?,?" (equivalente al "IN (?)" que mysql2 resuelve solo del lado de Node).
     *
     * @param array<int, mixed> $params
     * @return array<int, array<string, mixed>>
     */
    public static function query(string $sql, array $params = []): array
    {
        [$sql, $flat] = self::expandArrays($sql, $params);
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($flat);
        return $stmt->fetchAll();
    }

    /** @param array<int, mixed> $params */
    private static function expandArrays(string $sql, array $params): array
    {
        $flat = [];
        $i = 0;
        $out = preg_replace_callback('/\?/', function () use ($params, &$i, &$flat) {
            $p = $params[$i++] ?? null;
            if (is_array($p)) {
                if (count($p) === 0) {
                    // IN vacío: no debe matchear nada
                    $flat[] = null;
                    return '?';
                }
                foreach ($p as $v) {
                    $flat[] = $v;
                }
                return implode(',', array_fill(0, count($p), '?'));
            }
            $flat[] = $p;
            return '?';
        }, $sql);
        return [$out, $flat];
    }

    /** Nombre de base escapado (con backticks), para consultas entre bases del mismo servidor. */
    public static function ident(string $name): string
    {
        return '`' . str_replace('`', '``', $name) . '`';
    }
}
