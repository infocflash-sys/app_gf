<?php

declare(strict_types=1);

namespace App;

final class Routes
{
    // Pieza -> comprobante de ingreso -> cliente. Todo se filtra por los clientes de la sesión.
    private const FROM_OWNED = '
      FROM flash_piezas p
      JOIN flash_comprobantes_ingresos ci ON ci.id = p.comprobante_ingreso_id
      LEFT JOIN flash_piezas_estados_variables ev ON ev.id = p.estado_id';

    // En la pieza, localidad y provincia guardan el id de ubicacion_localidades / ubicacion_provincias.
    private const JOIN_LOC = '
      LEFT JOIN ubicacion_localidades ul ON ul.id = p.localidad_destino
      LEFT JOIN ubicacion_provincias pr ON pr.id = p.provincia_destino';

    private static function sendFile(array $f): void
    {
        header('Cache-Control: private, max-age=86400');
        header('Content-Type: ' . $f['mime']);
        header('Content-Length: ' . filesize($f['file']));
        readfile($f['file']);
    }

    private static function fail(array $r): void
    {
        Router::json($r['status'] ?? 400, ['error' => $r['error'], 'code' => $r['code']]);
    }

    private static function notFound(): void
    {
        Router::json(404, ['error' => 'Archivo no encontrado.', 'code' => 'NOT_FOUND']);
    }

    private static function piezaNotFound(): void
    {
        Router::json(404, ['error' => 'Pieza no encontrada.', 'code' => 'NOT_FOUND']);
    }

    private static function rateLimited(): void
    {
        Router::json(429, ['error' => 'Demasiados intentos. Probá de nuevo en un momento.', 'code' => 'RATE_LIMIT']);
    }

    private static function sinceOf(int $dias): string
    {
        // hora de Argentina (UTC-3): igual que sinceOf() en routes.js
        return gmdate('Y-m-d', time() - $dias * 86_400 - 3 * 3_600);
    }

    private static function clean(mixed $v): string
    {
        return is_string($v) ? trim($v) : '';
    }

    private static function mapPieza(array $r): array
    {
        // El nº de seguimiento que ve el cliente es el código externo; si faltara, el propio y por último el id.
        $tracking = self::clean($r['barcode_externo'] ?: null) ?: (self::clean($r['barcode'] ?: null) ?: (string) $r['id']);
        $remitoClean = self::clean($r['remito'] ?? null);
        return [
            'id' => (int) $r['id'],
            'tracking' => $tracking,
            'remito' => ($remitoClean !== '' && $remitoClean !== $tracking) ? $remitoClean : null,
            'destinatario' => $r['destinatario'],
            'localidad' => implode(', ', array_filter([$r['localidad_destino'] ?? null, $r['provincia'] ?? null])),
            'cantidad' => $r['cantidad'],
            'estadoId' => $r['estado_id'] !== null ? (int) $r['estado_id'] : null,
            'estado' => $r['estado'],
            'definitivo' => isset($r['grp']) && ((int) $r['grp']) === Config::get()->estadoDefinitivo,
            'fecha' => Util::toIso($r['fecha']),
            'actualizado' => Util::toIso($r['actualizado']),
        ];
    }

    /** Fila base de una pieza según un WHERE a medida (dueño por cliente_id, o por barcode exacto). */
    private static function detailRow(string $where, array $params): ?array
    {
        $rows = Db::query(
            'SELECT p.id, p.barcode, p.barcode_externo, p.remito, p.destinatario, p.domicilio, p.piso,
                    p.departamento_oficina, COALESCE(ul.nombre, p.localidad_destino) AS localidad_destino,
                    pr.nombre AS provincia, p.codigo_postal_destino AS cp, p.cantidad, p.docum_file, p.estado_id,
                    ev.nombre AS estado, ev.pieza_estado_id AS grp,
                    p.`create` AS fecha, p.`update` AS actualizado
             ' . self::FROM_OWNED . ' ' . self::JOIN_LOC . "
             WHERE {$where} LIMIT 1",
            $params,
        );
        return $rows[0] ?? null;
    }

    /** Arma el detalle completo (eventos, archivos, en vivo) a partir de la fila de detailRow(). */
    private static function buildDetail(array $p): array
    {
        $id = (int) $p['id'];
        $paqRows = Db::query('SELECT bultos, peso FROM flash_piezas_paquetes WHERE pieza_id = ? LIMIT 1', [$id]);
        $paq = $paqRows[0] ?? null;

        $tr = Db::query(
            'SELECT t.id, t.estado_id, ev.nombre AS estado, ev.pieza_estado_id AS grp,
                    t.`create` AS fecha, t.foto, t.firma_img
             FROM flash_piezas_tracking t
             LEFT JOIN flash_piezas_estados_variables ev ON ev.id = t.estado_id
             WHERE t.pieza_id = ? ORDER BY t.`create` DESC, t.id DESC',
            [$id],
        );

        $DEFINITIVO = Config::get()->estadoDefinitivo;
        $eventosRaw = array_map(static function (array $t) use ($DEFINITIVO): array {
            return [
                'id' => (int) $t['id'],
                'estadoId' => $t['estado_id'] !== null ? (int) $t['estado_id'] : null,
                'estado' => $t['estado'],
                'definitivo' => isset($t['grp']) && ((int) $t['grp']) === $DEFINITIVO,
                'fecha' => Util::toIso($t['fecha']),
                'foto' => Util::safeName($t['foto'], ['jpg', 'jpeg', 'png']) !== null,
                'firma' => Util::safeName($t['firma_img'], ['jpg', 'jpeg', 'png']) !== null,
                'fotoEventoId' => (int) $t['id'],
            ];
        }, $tr);
        $eventos = array_map(static function (array $e): array {
            unset($e['fotoEventoId']);
            return $e;
        }, Util::dedupeEvents($eventosRaw));

        $base = self::mapPieza($p);
        // "en vivo" = tiene recorrido abierto en ruteo, sin importar el estado_id (cubre también
        // el retiro de gestión 1/2, que arranca el recorrido antes de existir la HDR).
        $enVivo = in_array($id, Tracking::liveIds([$id]), true);

        return [
            ...$base,
            'enVivo' => $enVivo,
            'localidad' => $p['cp'] ? "{$base['localidad']} (CP {$p['cp']})" : $base['localidad'],
            'domicilio' => implode(', ', array_filter([
                $p['domicilio'],
                $p['piso'] ? "Piso {$p['piso']}" : null,
                $p['departamento_oficina'],
            ])),
            'bultos' => $paq['bultos'] ?? $p['cantidad'],
            'pesoKg' => $paq['peso'] ?? null,
            'pdf' => Util::safeName($p['docum_file'], ['pdf']) !== null,
            'eventos' => $eventos,
        ];
    }

    /** Fila mínima para el seguimiento en vivo, según un WHERE a medida. */
    private static function seguimientoRow(string $where, array $params): ?array
    {
        $rows = Db::query(
            'SELECT p.id, p.estado_id, ev.nombre AS estado ' . self::FROM_OWNED . " WHERE {$where} LIMIT 1",
            $params,
        );
        return $rows[0] ?? null;
    }

    public static function register(Router $router): void
    {
        $DEFINITIVO = Config::get()->estadoDefinitivo;

        // ---------- autenticación ----------
        $router->post('/auth/login', static function (Request $req): void {
            if (!RateLimit::allow('login', 10, 60)) {
                Router::json(429, ['error' => 'Demasiados intentos. Probá de nuevo en un momento.', 'code' => 'RATE_LIMIT']);
                return;
            }
            $r = Auth::login($req->bodyParam('usuario'), $req->bodyParam('clave'));
            if (isset($r['error'])) {
                self::fail($r);
                return;
            }
            Router::json(200, [...Auth::issueTokens($r['session']), ...Auth::profileOf($r['session'])]);
        });

        $router->post('/auth/refresh', static function (Request $req): void {
            $r = Auth::refresh($req->bodyParam('refreshToken'));
            if (isset($r['error'])) {
                self::fail($r);
                return;
            }
            Router::json(200, [...Auth::issueTokens($r['session']), ...Auth::profileOf($r['session'])]);
        });

        // Se llama al abrir la app: valida que la cuenta siga activa y devuelve el nombre del cliente.
        $router->get('/me', static function (Request $req, array $session): void {
            Router::json(200, Auth::profileOf($session));
        }, auth: true);

        // ---------- piezas ----------
        $router->get('/piezas', static function (Request $req, array $session) use ($DEFINITIVO): void {
            $ids = array_map(static fn (array $c) => $c['id'], $session['clientes']);
            $dias = min(max((int) ($req->queryParam('dias') ?: Config::get()->piezasDiasDefault), 1), 365);
            $page = max((int) ($req->queryParam('page') ?: 1), 1);
            $size = min(max((int) ($req->queryParam('size') ?: 30), 1), 100);
            $q = substr(trim((string) $req->queryParam('q')), 0, 60);
            $grupo = $req->queryParam('grupo'); // 'gestion' | 'finalizadas'

            $params = [$ids, self::sinceOf($dias)];
            $filtro = '';
            if ($q !== '') {
                $like = "%{$q}%";
                // Buscador universal: también matchea el nombre del estado/novedad (ej. "en distri" -> "En distribucion").
                $filtro .= ' AND (p.id = ? OR p.barcode LIKE ? OR p.barcode_externo LIKE ? OR p.remito LIKE ?
                            OR p.destinatario LIKE ? OR p.domicilio LIKE ? OR ul.nombre LIKE ? OR pr.nombre LIKE ?
                            OR ev.nombre LIKE ?)';
                $params[] = preg_match('/^\d{1,10}$/', $q) ? (int) $q : 0;
                array_push($params, $like, $like, $like, $like, $like, $like, $like, $like);
            }
            if ($grupo === 'finalizadas') {
                $filtro .= " AND ev.pieza_estado_id = {$DEFINITIVO}";
            }
            if ($grupo === 'gestion') {
                $filtro .= " AND (ev.pieza_estado_id IS NULL OR ev.pieza_estado_id <> {$DEFINITIVO})";
            }
            if ($grupo === 'en_recorrido') {
                // Piezas con recorrido abierto ahora mismo (listas para el mapa en vivo), sin
                // importar el estado_id: cubre también el retiro de gestión 1/2, que arranca el
                // recorrido antes de existir la HDR (la pieza sigue diciendo "Pendiente de Retiro").
                $R = Db::ident(Config::get()->ruteoDb);
                $recorridoAbierto = Config::get()->recorridoAbierto;
                $filtro .= " AND EXISTS (
                    SELECT 1 FROM {$R}.piezas rp
                    JOIN {$R}.asignacion a ON a.pieza_id = rp.id
                    JOIN {$R}.grupo_asignacion ga ON ga.id = a.grupo_asignacion_id
                    WHERE rp.pieza_id = p.id AND ga.estado = {$recorridoAbierto}
                )";
            }
            $limit = $size + 1;
            $offset = ($page - 1) * $size;

            $rows = Db::query(
                "SELECT p.id, p.barcode, p.barcode_externo, p.remito, p.destinatario,
                        COALESCE(ul.nombre, p.localidad_destino) AS localidad_destino, pr.nombre AS provincia,
                        p.cantidad, p.estado_id, ev.nombre AS estado, ev.pieza_estado_id AS grp,
                        p.`create` AS fecha, p.`update` AS actualizado
                 " . self::FROM_OWNED . ' ' . self::JOIN_LOC . "
                 WHERE ci.cliente_id IN (?) AND p.`create` >= ? {$filtro}
                 ORDER BY p.id DESC LIMIT {$limit} OFFSET {$offset}",
                $params,
            );

            $items = array_map(self::mapPieza(...), array_slice($rows, 0, $size));
            // "en vivo" = tiene recorrido abierto en ruteo, sin importar el estado_id.
            $live = Tracking::liveIds(array_map(static fn (array $i) => $i['id'], $items));
            foreach ($items as &$it) {
                $it['enVivo'] = in_array($it['id'], $live, true);
            }
            unset($it);

            $out = ['page' => $page, 'size' => $size, 'hasMore' => count($rows) > $size, 'items' => $items];

            if ($page === 1) {
                $cache = new TtlCache(Config::get()->cacheDir . '/resumen');
                $cacheKey = 'res:' . implode(',', $ids) . ':' . $dias;
                $out['resumen'] = $cache->get($cacheKey, 30, static function () use ($ids, $dias, $DEFINITIVO) {
                    $g = Db::query(
                        'SELECT ev.pieza_estado_id AS grp, COUNT(*) AS n ' . self::FROM_OWNED . '
                         WHERE ci.cliente_id IN (?) AND p.`create` >= ? GROUP BY ev.pieza_estado_id',
                        [$ids, self::sinceOf($dias)],
                    );
                    $fin = array_sum(array_map(
                        static fn (array $x) => ((int) $x['grp']) === $DEFINITIVO ? (int) $x['n'] : 0,
                        $g,
                    ));
                    $total = array_sum(array_map(static fn (array $x) => (int) $x['n'], $g));

                    // Recorrido abierto, sin importar el estado_id (ver nota en el filtro 'en_recorrido').
                    $R = Db::ident(Config::get()->ruteoDb);
                    $enRecorridoRows = Db::query(
                        'SELECT COUNT(*) AS n ' . self::FROM_OWNED . "
                         WHERE ci.cliente_id IN (?) AND p.`create` >= ? AND EXISTS (
                            SELECT 1 FROM {$R}.piezas rp
                            JOIN {$R}.asignacion a ON a.pieza_id = rp.id
                            JOIN {$R}.grupo_asignacion ga ON ga.id = a.grupo_asignacion_id
                            WHERE rp.pieza_id = p.id AND ga.estado = ?
                         )",
                        [$ids, self::sinceOf($dias), Config::get()->recorridoAbierto],
                    );

                    return [
                        'total' => $total,
                        'finalizadas' => $fin,
                        'enGestion' => $total - $fin,
                        'enRecorrido' => (int) $enRecorridoRows[0]['n'],
                        'dias' => $dias,
                    ];
                });
            }
            Router::json(200, $out);
        }, auth: true);

        $router->get('/piezas/:id', static function (Request $req, array $session): void {
            $id = (int) $req->param('id');
            $ids = array_map(static fn (array $c) => $c['id'], $session['clientes']);
            // si la pieza es de otro cliente se responde igual que si no existiera
            $p = self::detailRow('p.id = ? AND ci.cliente_id IN (?)', [$id, $ids]);
            if ($p === null) {
                self::piezaNotFound();
                return;
            }
            Router::json(200, self::buildDetail($p));
        }, auth: true);

        // ---------- archivos (siempre tras comprobar que la pieza es del cliente) ----------
        $owned = static function (array $session, int $id): ?array {
            $ids = array_map(static fn (array $c) => $c['id'], $session['clientes']);
            $rows = Db::query(
                'SELECT p.id, p.docum_file FROM flash_piezas p
                 JOIN flash_comprobantes_ingresos ci ON ci.id = p.comprobante_ingreso_id
                 WHERE p.id = ? AND ci.cliente_id IN (?) LIMIT 1',
                [$id, $ids],
            );
            return $rows[0] ?? null;
        };

        // kind: "foto" o "firma"; size: "thumb" o "full"
        $router->get('/piezas/:id/eventos/:eid/:kind', static function (Request $req, array $session) use ($owned): void {
            $id = (int) $req->param('id');
            $eid = (int) $req->param('eid');
            $kind = $req->param('kind');
            if (!in_array($kind, ['foto', 'firma'], true) || $owned($session, $id) === null) {
                self::notFound();
                return;
            }
            $rows = Db::query('SELECT foto, firma_img FROM flash_piezas_tracking WHERE id = ? AND pieza_id = ? LIMIT 1', [$eid, $id]);
            $t = $rows[0] ?? null;
            $name = Util::safeName($kind === 'foto' ? ($t['foto'] ?? null) : ($t['firma_img'] ?? null), ['jpg', 'jpeg', 'png']);
            if ($name === null) {
                self::notFound();
                return;
            }
            $f = Files::getImage($name, $req->queryParam('size') === 'full' ? 'full' : 'thumb');
            $f !== null ? self::sendFile($f) : self::notFound();
        }, auth: true);

        $router->get('/piezas/:id/pdf', static function (Request $req, array $session) use ($owned): void {
            $p = $owned($session, (int) $req->param('id'));
            $name = Util::safeName($p['docum_file'] ?? null, ['pdf']);
            if ($name === null) {
                self::notFound();
                return;
            }
            $f = Files::getPdf($name);
            $f !== null ? self::sendFile($f) : self::notFound();
        }, auth: true);

        // ---------- seguimiento en tiempo real ----------
        // Solo si la pieza es del cliente, está "En distribución" y su recorrido está abierto (estado 0).
        $router->get('/piezas/:id/seguimiento', static function (Request $req, array $session): void {
            $id = (int) $req->param('id');
            $ids = array_map(static fn (array $c) => $c['id'], $session['clientes']);
            $p = self::seguimientoRow('p.id = ? AND ci.cliente_id IN (?)', [$id, $ids]);
            if ($p === null) {
                self::piezaNotFound();
                return;
            }
            header('Cache-Control: no-store');
            Router::json(200, Tracking::trackingOf(
                (int) $p['id'],
                $p['estado_id'] !== null ? (int) $p['estado_id'] : null,
                $p['estado'] ?? '',
            ));
        }, auth: true);

        // ---------- acceso de destinatarios (sin login, por nº de seguimiento exacto) ----------
        // Pensado para quien recibe el envío pero no tiene cuenta en el TMS: solo ve ESA pieza,
        // nunca una lista. Coincidencia siempre exacta (nunca LIKE) para no exponer otras piezas.
        $router->get('/public/pieza/:barcode', static function (Request $req): void {
            if (!RateLimit::allow('public_pieza', 8, 60)) {
                self::rateLimited();
                return;
            }
            $barcode = self::clean($req->param('barcode'));
            $p = $barcode !== '' ? self::detailRow('(p.barcode_externo = ? OR p.barcode = ?)', [$barcode, $barcode]) : null;
            if ($p === null) {
                self::piezaNotFound();
                return;
            }
            Router::json(200, self::buildDetail($p));
        });

        $router->get('/public/pieza/:barcode/seguimiento', static function (Request $req): void {
            if (!RateLimit::allow('public_seguimiento', 40, 60)) {
                self::rateLimited();
                return;
            }
            $barcode = self::clean($req->param('barcode'));
            // se revalida el código en cada sondeo (no se confía en un id numérico ya resuelto):
            // así la única puerta de entrada sigue siendo conocer el nº de seguimiento real.
            $p = $barcode !== '' ? self::seguimientoRow('(p.barcode_externo = ? OR p.barcode = ?)', [$barcode, $barcode]) : null;
            if ($p === null) {
                self::piezaNotFound();
                return;
            }
            header('Cache-Control: no-store');
            Router::json(200, Tracking::trackingOf(
                (int) $p['id'],
                $p['estado_id'] !== null ? (int) $p['estado_id'] : null,
                $p['estado'] ?? '',
            ));
        });
    }
}
