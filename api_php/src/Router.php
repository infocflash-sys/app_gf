<?php

declare(strict_types=1);

namespace App;

/** Micro-router: matchea método + path (con parámetros ":nombre") contra handlers registrados. */
final class Router
{
    /** @var array<int, array{method:string,pattern:string,names:array<int,string>,regex:string,handler:callable,auth:bool}> */
    private array $routes = [];

    public function add(string $method, string $pattern, callable $handler, bool $auth = false): void
    {
        $names = [];
        $regex = preg_replace_callback('#:([A-Za-z_][A-Za-z0-9_]*)#', static function ($m) use (&$names) {
            $names[] = $m[1];
            return '([^/]+)';
        }, $pattern);
        $this->routes[] = [
            'method' => $method,
            'pattern' => $pattern,
            'names' => $names,
            'regex' => '#^' . $regex . '$#',
            'handler' => $handler,
            'auth' => $auth,
        ];
    }

    public function get(string $pattern, callable $handler, bool $auth = false): void
    {
        $this->add('GET', $pattern, $handler, $auth);
    }

    public function post(string $pattern, callable $handler, bool $auth = false): void
    {
        $this->add('POST', $pattern, $handler, $auth);
    }

    /** Despacha la request actual. Responde JSON salvo que el handler ya haya enviado el cuerpo (archivos). */
    public function dispatch(string $method, string $path): void
    {
        $path = rtrim(parse_url($path, PHP_URL_PATH) ?: '/', '/') ?: '/';
        foreach ($this->routes as $r) {
            if ($r['method'] !== $method) {
                continue;
            }
            if (!preg_match($r['regex'], $path, $m)) {
                continue;
            }
            array_shift($m);
            $params = array_combine($r['names'], $m);

            $session = null;
            if ($r['auth']) {
                $session = Auth::authenticate($_SERVER['HTTP_AUTHORIZATION'] ?? self::bearerFromApache());
                if (!($session['ok'] ?? false)) {
                    self::json((int) $session['status'], ['error' => $session['error'], 'code' => $session['code']]);
                    return;
                }
            }

            $req = new Request($params, $_GET, self::jsonBody());
            ($r['handler'])($req, $session);
            return;
        }
        self::json(404, ['error' => 'No encontrado.', 'code' => 'NOT_FOUND']);
    }

    /** Algunos servidores (CGI/FastCGI) no llenan HTTP_AUTHORIZATION salvo que se pida así. */
    private static function bearerFromApache(): ?string
    {
        if (function_exists('apache_request_headers')) {
            $h = apache_request_headers();
            return $h['Authorization'] ?? $h['authorization'] ?? null;
        }
        return $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? null;
    }

    private static function jsonBody(): array
    {
        $raw = file_get_contents('php://input');
        if (!$raw) {
            return [];
        }
        $data = json_decode($raw, true);
        return is_array($data) ? $data : [];
    }

    public static function json(int $status, mixed $payload): void
    {
        http_response_code($status);
        header('Content-Type: application/json; charset=utf-8');
        echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    }
}
