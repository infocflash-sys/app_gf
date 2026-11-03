<?php

declare(strict_types=1);

namespace App;

final class Tracking
{
    private const POS_TTL_SECONDS = 15;
    private const CIRCUIT_TTL_SECONDS = 10;

    /** La app del cartero captura una coordenada cada 20 s pero sube el lote una vez por minuto. */
    private const RECENT_TRAIL_MAX = 3;

    private static function cache(): TtlCache
    {
        static $c = null;
        return $c ??= new TtlCache(Config::get()->cacheDir . '/tracking');
    }

    /**
     * Elige el punto de la pieza dentro del recorrido: si la pieza espera un retiro se muestra el retiro,
     * si no la entrega (y si solo hay retiro, el retiro). Las coordenadas vienen como texto en la DB.
     *
     * @param array<int, array<string, mixed>> $rows
     */
    public static function pickStop(array $rows, string $estadoNombre = ''): ?array
    {
        $stops = [];
        foreach ($rows as $r) {
            if ($r['tipo'] !== 'ENTREGA' && $r['tipo'] !== 'RETIRO') {
                continue;
            }
            // a diferencia de JS (parseFloat da NaN con texto no numérico), (float)'abc' da 0.0:
            // hay que validar con is_numeric antes de convertir.
            if (!is_numeric($r['latitud']) || !is_numeric($r['longitud'])) {
                continue;
            }
            $lat = (float) $r['latitud'];
            $lng = (float) $r['longitud'];
            if ($lat === 0.0 && $lng === 0.0) {
                continue;
            }
            $stops[] = ['tipo' => $r['tipo'], 'lat' => $lat, 'lng' => $lng];
        }
        $retiro = null;
        $entrega = null;
        foreach ($stops as $s) {
            if ($s['tipo'] === 'RETIRO' && $retiro === null) {
                $retiro = $s;
            }
            if ($s['tipo'] === 'ENTREGA' && $entrega === null) {
                $entrega = $s;
            }
        }
        if (preg_match('/retiro/i', $estadoNombre) && $retiro !== null) {
            return $retiro;
        }
        return $entrega ?? $retiro;
    }

    /** Posición del vehículo con su antigüedad y si se considera "sin señal reciente". */
    public static function describePosition(?array $pos, ?int $nowTs = null): ?array
    {
        if ($pos === null) {
            return null;
        }
        $nowTs ??= time();
        $segundos = max(0, $nowTs - $pos['fechaTs']);
        return [
            'lat' => $pos['lat'],
            'lng' => $pos['lng'],
            'fecha' => Util::toIso($pos['fechaDb']),
            'segundos' => $segundos,
            'sinSenal' => $segundos > Config::get()->segundosSinSenal,
        ];
    }

    /**
     * Última posición conocida de un cartero (ventana de 24 h, desempate por id).
     * Cacheada 15 s en disco (equivalente a la caché compartida de Node, pero por cartero:
     * cada request de PHP resuelve la suya, no hay "demanda" acumulada entre requests).
     */
    public static function positionOf(int $carteroId): ?array
    {
        return self::cache()->get("pos:{$carteroId}", self::POS_TTL_SECONDS, static function () use ($carteroId): ?array {
            $rows = Db::query(
                'SELECT id, Latitude AS lat, Longitude AS lng, FechaLocal AS fecha
                 FROM cartero_gps
                 WHERE cartero_id = ? AND FechaLocal >= NOW() - INTERVAL 24 HOUR
                 ORDER BY FechaLocal DESC, id DESC LIMIT 1',
                [$carteroId],
            );
            if (!$rows) {
                return null;
            }
            $r = $rows[0];
            return [
                'lat' => (float) $r['lat'],
                'lng' => (float) $r['lng'],
                'fechaDb' => $r['fecha'],
                // Hay que pasar por toIso() (fija "-03:00" explícito) ANTES de strtotime():
                // la DB guarda hora de Argentina sin offset, y sin esto PHP la interpreta con
                // el timezone del servidor (normalmente UTC), desfasando ~3 h el cálculo de antigüedad.
                'fechaTs' => strtotime(Util::toIso($r['fecha'])),
            ];
        });
    }

    /**
     * Hasta las últimas RECENT_TRAIL_MAX posiciones del cartero (de más vieja a más nueva).
     * Su app sube el lote una vez por minuto aunque capture una coordenada cada 20 s: en vez de
     * animar solo la lectura más nueva y quedar "congelada" hasta la próxima subida, la app arma
     * la cadena real con estos puntos y reparte el movimiento entre ellos.
     *
     * @return array<int, array{lat: float, lng: float, fecha: ?string}>
     */
    public static function recentPositions(int $carteroId): array
    {
        return self::cache()->get("recent:{$carteroId}", self::POS_TTL_SECONDS, static function () use ($carteroId): array {
            $rows = Db::query(
                'SELECT Latitude AS lat, Longitude AS lng, FechaLocal AS fecha
                 FROM cartero_gps
                 WHERE cartero_id = ? AND FechaLocal >= NOW() - INTERVAL 24 HOUR
                 ORDER BY FechaLocal DESC, id DESC LIMIT ' . self::RECENT_TRAIL_MAX,
                [$carteroId],
            );
            return array_reverse(array_map(static fn (array $r): array => [
                'lat' => (float) $r['lat'],
                'lng' => (float) $r['lng'],
                'fecha' => Util::toIso($r['fecha']),
            ], $rows));
        });
    }

    /**
     * Circuito: flash_piezas.id -> ruteo.piezas.pieza_id -> ruteo.piezas.id -> asignacion.pieza_id
     *           -> asignacion.grupo_asignacion_id (= recorrido) -> grupo_asignacion.id (estado 0) -> id_cartero
     */
    private static function circuitOf(int $piezaId): ?array
    {
        return self::cache()->get("c:{$piezaId}", self::CIRCUIT_TTL_SECONDS, static function () use ($piezaId): ?array {
            $r = Config::get()->ruteoDb;
            $R = Db::ident($r);
            $rows = Db::query(
                "SELECT rp.id AS rid, a.grupo_asignacion_id AS recorrido, ga.id_cartero AS cartero
                 FROM {$R}.piezas rp
                 JOIN {$R}.asignacion a ON a.pieza_id = rp.id
                 JOIN {$R}.grupo_asignacion ga ON ga.id = a.grupo_asignacion_id
                 WHERE rp.pieza_id = ? AND ga.estado = ?
                 ORDER BY ga.id DESC LIMIT 1",
                [$piezaId, Config::get()->recorridoAbierto],
            );
            return $rows[0] ?? null;
        });
    }

    /**
     * Ids (de flash_piezas) que están hoy en un recorrido abierto, para marcar "en vivo" en la lista.
     *
     * @param array<int, int> $piezaIds
     * @return array<int, int>
     */
    public static function liveIds(array $piezaIds): array
    {
        if (!$piezaIds) {
            return [];
        }
        $R = Db::ident(Config::get()->ruteoDb);
        $rows = Db::query(
            "SELECT DISTINCT rp.pieza_id
             FROM {$R}.piezas rp
             JOIN {$R}.asignacion a ON a.pieza_id = rp.id
             JOIN {$R}.grupo_asignacion ga ON ga.id = a.grupo_asignacion_id
             WHERE rp.pieza_id IN (?) AND ga.estado = ?",
            [$piezaIds, Config::get()->recorridoAbierto],
        );
        return array_map(static fn (array $r) => (int) $r['pieza_id'], $rows);
    }

    /** El seguimiento en vivo solo existe mientras la pieza está "En distribución". */
    public static function enDistribucion(?int $estadoId): bool
    {
        return $estadoId === Config::get()->estadoEnDistribucion;
    }

    /**
     * Hora en que el cartero salió "a la calle" hoy: primer punto GPS del día para ese cartero.
     * Se usa `cartero_gps.FechaLocal` (DATETIME, hora de Argentina tal cual se guarda) en vez de
     * `grupo_asignacion.fecha_creacion` (TIMESTAMP): esta última depende del time_zone de la sesión
     * de MySQL y da valores distintos según la conexión, el mismo tipo de bug que ya corregimos.
     */
    private static function inicioRecorrido(int $carteroId): ?string
    {
        return self::cache()->get("inicio:{$carteroId}:" . date('Y-m-d'), 300, static function () use ($carteroId): ?string {
            $rows = Db::query(
                'SELECT MIN(FechaLocal) AS inicio FROM cartero_gps
                 WHERE cartero_id = ? AND FechaLocal >= CURDATE()',
                [$carteroId],
            );
            return $rows[0]['inicio'] ?? null;
        });
    }

    /**
     * Seguimiento de una pieza. Solo se busca la posición del móvil si se cumplen las dos condiciones:
     *  1) la pieza está "En distribución", y
     *  2) su recorrido está ABIERTO (ruteo.grupo_asignacion.estado = 0).
     */
    public static function trackingOf(int $piezaId, ?int $estadoId, string $estado = ''): array
    {
        if (!self::enDistribucion($estadoId)) {
            return ['activo' => false];
        }
        $c = self::circuitOf($piezaId);
        if ($c === null) {
            return ['activo' => false];
        }

        $R = Db::ident(Config::get()->ruteoDb);
        $detalle = Db::query(
            "SELECT tipo, latitud, longitud, orden_recorrido
             FROM {$R}.grupo_asignacion_pieza_detalle
             WHERE grupo_asignacion_id = ? AND pieza_id = ?",
            [$c['recorrido'], $c['rid']],
        );
        $stop = self::pickStop($detalle, $estado);
        $cartero = $c['cartero'] !== null ? (int) $c['cartero'] : null;
        $pos = $cartero !== null ? self::positionOf($cartero) : null;

        return [
            'activo' => true,
            'recorrido' => $c['recorrido'],
            'tipo' => $stop['tipo'] ?? null,
            'destino' => $stop !== null ? ['lat' => $stop['lat'], 'lng' => $stop['lng']] : null,
            'vehiculo' => self::describePosition($pos),
            'puntosRecientes' => $cartero !== null ? self::recentPositions($cartero) : [],
            'inicioRecorrido' => $cartero !== null ? Util::toIso(self::inicioRecorrido($cartero)) : null,
        ];
    }
}
