<?php

declare(strict_types=1);

namespace App;

use Firebase\JWT\ExpiredException;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;

final class Auth
{
    private const MESSAGES = [
        'ACCOUNT_DISABLED' => 'Tu cuenta no está habilitada. Comunicate con Grupo Flash.',
        'NOT_CLIENT' => 'Esta aplicación es solo para clientes.',
        'CLIENT_DISABLED' => 'Tu cuenta de cliente no está activa. Comunicate con Grupo Flash.',
        'REVOKED' => 'Tu sesión ya no es válida. Ingresá nuevamente.',
    ];

    private static ?TtlCache $sessions = null;
    private const SESSION_TTL_SECONDS = 60; // el estado activo se revalida como máximo cada minuto

    private static function sessions(): TtlCache
    {
        return self::$sessions ??= new TtlCache(Config::get()->cacheDir . '/sessions');
    }

    /**
     * Verifica la clave con el esquema de Ion Auth que usa el ERP:
     * hash = sal(10) + sha1(sal + clave) sin los últimos 10 caracteres.
     */
    public static function ionAuthVerify(string $password, ?string $stored): bool
    {
        if ($stored === null || strlen($stored) !== 40) {
            return false;
        }
        $salt = substr($stored, 0, 10);
        $calc = $salt . substr(sha1($salt . $password), 0, -10);
        return hash_equals($stored, $calc);
    }

    /** Huella de la clave: si la clave cambia en el ERP, las sesiones viejas dejan de valer. */
    private static function fingerprint(?string $hash): string
    {
        return substr(hash_hmac('sha256', $hash ?? '', Config::get()->jwtSecret), 0, 16);
    }

    /** @return array{id:int,username:string,nombre:?string,apellido:?string,active:bool,hash:?string,isCliente:bool,clientes:array}|null */
    private static function loadAccount(int $userId): ?array
    {
        $rows = Db::query('SELECT id, active, password, username, nombre, apellido FROM users WHERE id = ? LIMIT 1', [$userId]);
        if (!$rows) {
            return null;
        }
        $u = $rows[0];
        $groups = array_map(
            static fn (array $r) => (int) $r['group_id'],
            Db::query('SELECT group_id FROM users_groups WHERE user_id = ?', [$userId]),
        );
        $clientes = Db::query('SELECT id, nombre, cliente_estado_id AS estado FROM flash_clientes WHERE user_id = ?', [$userId]);

        return [
            'id' => (int) $u['id'],
            'username' => (string) $u['username'],
            'nombre' => $u['nombre'],
            'apellido' => $u['apellido'],
            'active' => ((int) $u['active']) === 1,
            'hash' => $u['password'],
            'isCliente' => in_array(Config::get()->groupCliente, $groups, true),
            'clientes' => $clientes,
        ];
    }

    /** Reglas de acceso: usuario activo, del grupo Cliente y con al menos un cliente Activo. */
    private static function evaluate(?array $acc): array
    {
        if ($acc === null || !$acc['active']) {
            return ['ok' => false, 'code' => 'ACCOUNT_DISABLED'];
        }
        if (!$acc['isCliente']) {
            return ['ok' => false, 'code' => 'NOT_CLIENT'];
        }
        $activos = array_values(array_filter(
            $acc['clientes'],
            fn (array $c) => ((int) $c['estado']) === Config::get()->clienteActivo,
        ));
        if (!$activos) {
            return ['ok' => false, 'code' => 'CLIENT_DISABLED'];
        }
        $clientes = array_map(
            static fn (array $c) => ['id' => (int) $c['id'], 'nombre' => trim((string) $c['nombre'])],
            $activos,
        );
        return [
            'ok' => true,
            'userId' => $acc['id'],
            'fp' => self::fingerprint($acc['hash']),
            'nombre' => self::welcomeName($clientes, $acc),
            'clientes' => $clientes,
        ];
    }

    /**
     * Nombre para la bienvenida: con un solo cliente, el nombre del cliente;
     * si el usuario tiene varios clientes, el nombre del usuario (o su usuario si no tiene nombre cargado).
     */
    public static function welcomeName(array $clientes, array $user): string
    {
        if (count($clientes) <= 1) {
            return $clientes[0]['nombre'];
        }
        $full = trim(preg_replace('/\s+/', ' ', (($user['nombre'] ?? '') . ' ' . ($user['apellido'] ?? ''))));
        return $full !== '' ? $full : (trim((string) ($user['username'] ?? '')) ?: $clientes[0]['nombre']);
    }

    public static function messageFor(string $code): string
    {
        return self::MESSAGES[$code] ?? 'No se pudo validar la sesión.';
    }

    /** @return array{accessToken:string,refreshToken:string} */
    public static function issueTokens(array $s): array
    {
        $now = time();
        $sign = static function (string $typ, int $ttl) use ($s, $now): string {
            return JWT::encode([
                'sub' => (string) $s['userId'],
                'fp' => $s['fp'],
                'typ' => $typ,
                'iat' => $now,
                'exp' => $now + $ttl,
            ], Config::get()->jwtSecret, 'HS256');
        };
        return [
            'accessToken' => $sign('access', Config::get()->accessTtlSeconds),
            'refreshToken' => $sign('refresh', Config::get()->refreshTtlSeconds),
        ];
    }

    public static function profileOf(array $s): array
    {
        return ['cliente' => $s['nombre'], 'clientes' => $s['clientes']];
    }

    // ---- bloqueo por intentos fallidos (persistido en disco con lectura-modificación-escritura atómica) ----
    private const MAX_FAILS = 5;
    private const LOCK_SECONDS = 5 * 60;

    private static function failsDir(): string
    {
        $dir = Config::get()->cacheDir . '/fails';
        if (!is_dir($dir)) {
            mkdir($dir, 0775, true);
        }
        return $dir;
    }

    private static function failsFile(string $user): string
    {
        return self::failsDir() . '/' . sha1(strtolower($user)) . '.json';
    }

    /** Abre (o crea) el archivo del usuario con lock exclusivo y aplica $mutator sobre su estado. */
    private static function withFailsLock(string $user, callable $mutator): mixed
    {
        $fp = fopen(self::failsFile($user), 'c+');
        if ($fp === false) {
            return $mutator(['n' => 0, 'until' => 0]);
        }
        try {
            flock($fp, LOCK_EX);
            $raw = stream_get_contents($fp);
            $state = $raw !== false && $raw !== '' ? (json_decode($raw, true) ?: ['n' => 0, 'until' => 0]) : ['n' => 0, 'until' => 0];
            [$result, $next] = $mutator($state);
            if ($next !== null) {
                ftruncate($fp, 0);
                rewind($fp);
                fwrite($fp, json_encode($next));
            } else {
                ftruncate($fp, 0);
            }
            return $result;
        } finally {
            flock($fp, LOCK_UN);
            fclose($fp);
        }
    }

    private static function locked(string $user): bool
    {
        if (!is_file(self::failsFile($user))) {
            return false;
        }
        return self::withFailsLock($user, static fn (array $f) => [($f['until'] ?? 0) > time(), $f]);
    }

    private static function registerFail(string $user): void
    {
        self::withFailsLock($user, static function (array $f): array {
            $f['n'] = ($f['n'] ?? 0) + 1;
            if ($f['n'] >= self::MAX_FAILS) {
                $f['until'] = time() + self::LOCK_SECONDS;
                $f['n'] = 0;
            }
            return [null, $f];
        });
    }

    private static function clearFails(string $user): void
    {
        @unlink(self::failsFile($user));
    }

    /** @return array{error?:string,code?:string,status?:int,session?:array} */
    public static function login(?string $username, ?string $password): array
    {
        $user = trim((string) $username);
        if ($user === '' || $password === null || $password === '') {
            return ['error' => 'Completá usuario y clave.', 'code' => 'EMPTY', 'status' => 400];
        }
        if (self::locked($user)) {
            return ['error' => 'Demasiados intentos. Probá de nuevo en unos minutos.', 'code' => 'LOCKED', 'status' => 429];
        }
        $row = Db::query('SELECT id FROM users WHERE username = ? LIMIT 1', [$user]);
        $acc = $row ? self::loadAccount((int) $row[0]['id']) : null;
        // la clave se verifica ANTES de decir nada sobre el estado de la cuenta
        if ($acc === null || !self::ionAuthVerify((string) $password, $acc['hash'])) {
            self::registerFail($user);
            return ['error' => 'Usuario o clave incorrectos.', 'code' => 'BAD_CREDENTIALS', 'status' => 401];
        }
        self::clearFails($user);
        $s = self::evaluate($acc);
        if (!$s['ok']) {
            return ['error' => self::messageFor($s['code']), 'code' => $s['code'], 'status' => 403];
        }
        self::sessions()->delete((string) $s['userId']);
        return ['session' => $s];
    }

    /** Estado vigente de una sesión (con caché corta en disco). */
    public static function getSession(int $userId, ?string $fp): array
    {
        $s = self::sessions()->get((string) $userId, self::SESSION_TTL_SECONDS, static fn () => self::evaluate(self::loadAccount($userId)));
        if (!$s['ok']) {
            return $s;
        }
        if ($fp !== null && $s['fp'] !== $fp) {
            return ['ok' => false, 'code' => 'REVOKED'];
        }
        return $s;
    }

    /** @return object */
    private static function verify(string $token, string $typ): object
    {
        $payload = JWT::decode($token, new Key(Config::get()->jwtSecret, 'HS256'));
        if (($payload->typ ?? null) !== $typ) {
            throw new \UnexpectedValueException('tipo de token incorrecto');
        }
        return $payload;
    }

    /** @return array{error?:string,code?:string,status?:int,session?:array} */
    public static function refresh(?string $refreshToken): array
    {
        if ($refreshToken === null || $refreshToken === '') {
            return ['error' => 'Sesión no válida.', 'code' => 'BAD_TOKEN', 'status' => 401];
        }
        try {
            $p = self::verify($refreshToken, 'refresh');
        } catch (\Throwable) {
            return ['error' => 'Sesión no válida.', 'code' => 'BAD_TOKEN', 'status' => 401];
        }
        $s = self::getSession((int) $p->sub, $p->fp ?? null);
        if (!$s['ok']) {
            return ['error' => self::messageFor($s['code']), 'code' => $s['code'], 'status' => $s['code'] === 'REVOKED' ? 401 : 403];
        }
        return ['session' => $s];
    }

    /**
     * Exige sesión válida a partir del header Authorization y devuelve la sesión,
     * o un array de error (con "status") para que el router responda y corte.
     *
     * @return array{ok:true,userId:int,fp:string,nombre:string,clientes:array}|array{error:string,code:string,status:int}
     */
    public static function authenticate(?string $authHeader): array
    {
        if (!preg_match('/^Bearer (.+)$/', (string) $authHeader, $m)) {
            return ['error' => 'Sesión requerida.', 'code' => 'NO_TOKEN', 'status' => 401];
        }
        try {
            $p = self::verify($m[1], 'access');
        } catch (ExpiredException) {
            return ['error' => 'Sesión vencida.', 'code' => 'TOKEN_EXPIRED', 'status' => 401];
        } catch (\Throwable) {
            return ['error' => 'Sesión no válida.', 'code' => 'BAD_TOKEN', 'status' => 401];
        }
        $s = self::getSession((int) $p->sub, $p->fp ?? null);
        if (!$s['ok']) {
            return [
                'error' => self::messageFor($s['code']),
                'code' => $s['code'],
                'status' => $s['code'] === 'REVOKED' ? 401 : 403,
            ];
        }
        return $s;
    }
}
