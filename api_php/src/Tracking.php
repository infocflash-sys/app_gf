<?php

declare(strict_types=1);

namespace App;

final class Tracking
{
    private const POS_TTL_SECONDS = 15;
    private const CIRCUIT_TTL_SECONDS = 10;

    /**
     * La app del cartero captura una coordenada cada 20 s pero sube el lote una vez por minuto
     * (~3 puntos nuevos por subida). Se piden bastantes más de los 3 mínimos para mantener un
     * colchón de lecturas: así la animación nunca se queda sin tramos para encadenar aunque algún
     * sondeo del cliente se pierda, y la app arranca con más historial para una curva más fluida.
     */
    private const RECENT_TRAIL_MAX = 12;

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
     * true si, dentro del mismo recorrido, ninguna otra pieza con parada de ENTREGA todavía
     * pendiente ("En distribución") tiene un orden_recorrido menor que $miOrden: o sea, es la
     * próxima que el cartero va a entregar. No mira retiros ni piezas ya resueltas.
     */
    private static function esProximaEntrega(int $recorridoId, int $miOrden): bool
    {
        return self::cache()->get("prox:{$recorridoId}:{$miOrden}", self::CIRCUIT_TTL_SECONDS, static function () use ($recorridoId, $miOrden): bool {
            $R = Db::ident(Config::get()->ruteoDb);
            $rows = Db::query(
                "SELECT MIN(d.orden_recorrido) AS mino
                 FROM {$R}.grupo_asignacion_pieza_detalle d
                 JOIN {$R}.piezas rp ON rp.id = d.pieza_id
                 JOIN flash_piezas p ON p.id = rp.pieza_id
                 WHERE d.grupo_asignacion_id = ? AND d.tipo = 'ENTREGA' AND p.estado_id = ?",
                [$recorridoId, Config::get()->estadoEnDistribucion],
            );
            $mino = $rows[0]['mino'] ?? null;
            return $mino !== null && (int) $mino === $miOrden;
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
     * Estados ("enviado a...") con el despacho todavía EN CIRCULACIÓN (sin recepcionar):
     * las 21 variantes "Enviado a <sucursal>"/"Enviado Suc <sucursal>", "En tránsito" y
     * "En tránsito a Cliente". Deliberadamente más angosto que el agrupador
     * `pieza_estado_id = 4` del catálogo (ese grupo mezcla "En distribución", "Pendiente de
     * Retiro/Recepción" y los despachos vía Correo, que no aplican acá).
     */
    private const ESTADOS_EN_TRANSITO = [
        15, 34, 35, 36, 37, 38, 39, 40, 56, 61, 66, 67, 69, 71, 73, 75, 77, 79, 87, 89, 92, 96, 97,
    ];

    /**
     * Estados "Recibido en <sucursal>" (despacho ya recepcionado, pieza parada en esa sucursal
     * esperando su próximo movimiento). No incluye los "Recibido en/despacho Sucursal de Correo"
     * (33, 52): esos los maneja Correo Argentino y no tienen despacho interno con coordenadas.
     */
    private const ESTADOS_RECIBIDO_EN_SUCURSAL = [
        41, 42, 43, 44, 45, 46, 57, 60, 64, 65, 70, 72, 74, 76, 78, 80, 88, 90, 94, 98, 99,
    ];

    /**
     * Despacho que contiene esta pieza (traslado interno entre sucursales), el más reciente que
     * cumpla la condición pedida: $abierto=true busca uno EN CIRCULACIÓN (sin recepcionar),
     * $abierto=false busca el último YA RECEPCIONADO (para el pin estático en destino).
     * `transporte_id` es el id de cartero del transportista asignado (misma tabla
     * `flash_sucursales_carteros`, misma `cartero_gps`).
     */
    private static function despachoDe(int $piezaId, bool $abierto): ?array
    {
        $cond = $abierto ? 'd.fecha_recepcion IS NULL' : 'd.fecha_recepcion IS NOT NULL';
        return self::cache()->get('desp' . ($abierto ? 'a' : 'r') . ":{$piezaId}", self::CIRCUIT_TTL_SECONDS, static function () use ($piezaId, $cond): ?array {
            $rows = Db::query(
                "SELECT d.id AS despacho_id, d.transporte_id, d.destino_id, d.fecha_recepcion
                 FROM flash_piezas_despacho_piezas dp
                 JOIN flash_piezas_despacho d ON d.id = dp.despacho_id
                 WHERE dp.pieza_id = ? AND {$cond}
                 ORDER BY d.id DESC LIMIT 1",
                [$piezaId],
            );
            return $rows[0] ?? null;
        });
    }

    /** Coordenadas registradas de una sucursal (no todas las tienen cargadas). */
    private static function coordenadasSucursal(int $sucursalId): ?array
    {
        return self::cache()->get("sucoord:{$sucursalId}", 300, static function () use ($sucursalId): ?array {
            $rows = Db::query(
                'SELECT s.nombre, c.latitud, c.longitud
                 FROM flash_sucursales_coordenadas c
                 JOIN flash_sucursales s ON s.id = c.sucursal_id
                 WHERE c.sucursal_id = ? LIMIT 1',
                [$sucursalId],
            );
            return $rows[0] ?? null;
        });
    }

    /** B) Pieza en circulación entre sucursales (despacho sin recepcionar): sigue al transportista. */
    private static function trackingEnTransito(int $piezaId): array
    {
        $d = self::despachoDe($piezaId, abierto: true);
        if ($d === null) {
            return ['activo' => false];
        }
        $cartero = $d['transporte_id'] !== null ? (int) $d['transporte_id'] : null;
        $pos = $cartero !== null ? self::positionOf($cartero) : null;
        $suc = $d['destino_id'] !== null ? self::coordenadasSucursal((int) $d['destino_id']) : null;

        return [
            'activo' => true,
            'recorrido' => null,
            'tipo' => 'TRASLADO',
            'destino' => $suc !== null ? ['lat' => (float) $suc['latitud'], 'lng' => (float) $suc['longitud']] : null,
            'destinoNombre' => $suc['nombre'] ?? null,
            'vehiculo' => self::describePosition($pos),
            'puntosRecientes' => $cartero !== null ? self::recentPositions($cartero) : [],
            'inicioRecorrido' => $cartero !== null ? Util::toIso(self::inicioRecorrido($cartero)) : null,
            'proximaEntrega' => false,
        ];
    }

    /** C) Pieza parada en una sucursal (despacho ya recepcionado): pin fijo, sin vehículo. */
    private static function trackingEnSucursal(int $piezaId): array
    {
        $d = self::despachoDe($piezaId, abierto: false);
        $suc = $d !== null && $d['destino_id'] !== null ? self::coordenadasSucursal((int) $d['destino_id']) : null;
        if ($suc === null) {
            return ['activo' => false];
        }

        return [
            'activo' => true,
            'recorrido' => null,
            'tipo' => 'EN_SUCURSAL',
            'destino' => ['lat' => (float) $suc['latitud'], 'lng' => (float) $suc['longitud']],
            'destinoNombre' => $suc['nombre'],
            'vehiculo' => null,
            'puntosRecientes' => [],
            'inicioRecorrido' => null,
            'proximaEntrega' => false,
        ];
    }

    /**
     * Seguimiento de una pieza. Tres circuitos posibles, en este orden de prioridad:
     *  A) Recorrido ABIERTO en `ruteo` (ruteo.grupo_asignacion.estado = 0), sin importar el
     *     estado_id: cubre tanto el reparto al destinatario final como el retiro de tipos de
     *     gestión 1/2 (el recorrido de retiro se crea ANTES que la HDR, con la pieza todavía en
     *     "Pendiente de Retiro"). Si el mismo recorrido trae retiro Y entrega (gestión tipo 1,
     *     mismo día), se devuelven AMBAS paradas en `paradas`.
     *  B) Sin recorrido abierto, pero el estado es "Enviado a.../En tránsito" (`ESTADOS_EN_TRANSITO`):
     *     traslado interno entre sucursales, todavía circulando. Sigue al transportista del
     *     despacho (`transporte_id`), no a un cartero de reparto.
     *  C) Sin recorrido abierto, estado "Recibido en..." (`ESTADOS_RECIBIDO_EN_SUCURSAL`): el
     *     despacho ya fue recepcionado. Pin fijo en esa sucursal, sin vehículo (nada se mueve
     *     hasta que se le asigne un nuevo recorrido, que automáticamente vuelve a priorizar A).
     */
    public static function trackingOf(int $piezaId, ?int $estadoId, string $estado = ''): array
    {
        $c = self::circuitOf($piezaId);
        if ($c === null) {
            if ($estadoId !== null && in_array($estadoId, self::ESTADOS_EN_TRANSITO, true)) {
                return self::trackingEnTransito($piezaId);
            }
            if ($estadoId !== null && in_array($estadoId, self::ESTADOS_RECIBIDO_EN_SUCURSAL, true)) {
                return self::trackingEnSucursal($piezaId);
            }
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

        // Todas las paradas distintas de este recorrido para esta pieza (normalmente 1; en
        // gestión tipo 1 -retiro y entrega el mismo día- puede haber 2: RETIRO y ENTREGA).
        $paradas = [];
        $vistos = [];
        $miOrden = null;
        foreach ($detalle as $d) {
            if ($d['tipo'] === 'ENTREGA' && $miOrden === null) {
                $miOrden = (int) $d['orden_recorrido'];
            }
            if (($d['tipo'] === 'RETIRO' || $d['tipo'] === 'ENTREGA') && !isset($vistos[$d['tipo']])
                && is_numeric($d['latitud']) && is_numeric($d['longitud'])
            ) {
                $vistos[$d['tipo']] = true;
                $paradas[] = ['tipo' => $d['tipo'], 'lat' => (float) $d['latitud'], 'lng' => (float) $d['longitud']];
            }
        }

        return [
            'activo' => true,
            'recorrido' => $c['recorrido'],
            'tipo' => $stop['tipo'] ?? null,
            'destino' => $stop !== null ? ['lat' => $stop['lat'], 'lng' => $stop['lng']] : null,
            'paradas' => $paradas,
            'vehiculo' => self::describePosition($pos),
            'puntosRecientes' => $cartero !== null ? self::recentPositions($cartero) : [],
            'inicioRecorrido' => $cartero !== null ? Util::toIso(self::inicioRecorrido($cartero)) : null,
            'proximaEntrega' => $miOrden !== null && self::esProximaEntrega($c['recorrido'], $miOrden),
        ];
    }
}
