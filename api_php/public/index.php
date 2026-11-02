<?php

declare(strict_types=1);

namespace App;

require dirname(__DIR__) . '/vendor/autoload.php';

error_reporting(E_ALL);
ini_set('display_errors', '0'); // nunca mostrar errores crudos al cliente; se loguean abajo

set_exception_handler(static function (\Throwable $e): void {
    error_log('[api_php] ' . $e->getMessage() . "\n" . $e->getTraceAsString());
    $payload = ['error' => 'Error interno. Intentá de nuevo en un momento.', 'code' => 'SERVER_ERROR'];
    // Solo mientras probamos sin acceso a logs: con APP_DEBUG=1 en el .env, el JSON trae el detalle real.
    // Sacar APP_DEBUG del .env (o ponerlo en 0) antes de pasar esto a producción de verdad.
    if (($_ENV['APP_DEBUG'] ?? getenv('APP_DEBUG')) === '1') {
        $payload['debug'] = [
            'exception' => get_class($e),
            'message' => $e->getMessage(),
            'file' => $e->getFile() . ':' . $e->getLine(),
            'trace' => explode("\n", $e->getTraceAsString()),
        ];
    }
    Router::json(500, $payload);
});

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path = '/' . ltrim((string) ($_GET['__route'] ?? ''), '/');

if ($path === '/health') {
    Db::query('SELECT 1');
    Router::json(200, ['ok' => true]);
    return;
}

// Límite general (equivalente al plugin @fastify/rate-limit de Node: 600 por minuto por IP).
if (!RateLimit::allow('global', 600, 60)) {
    Router::json(429, ['error' => 'Demasiados pedidos. Probá de nuevo en un momento.', 'code' => 'RATE_LIMIT']);
    return;
}

$router = new Router();
Routes::register($router);
$router->dispatch($method, $path);
