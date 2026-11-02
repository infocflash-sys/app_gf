<?php

declare(strict_types=1);

namespace App;

/** Envoltorio simple de los datos de la request: params de ruta, query string y body JSON. */
final class Request
{
    public function __construct(
        public readonly array $params,
        public readonly array $query,
        public readonly array $body,
    ) {
    }

    public function param(string $name): ?string
    {
        return $this->params[$name] ?? null;
    }

    public function queryParam(string $name): ?string
    {
        $v = $this->query[$name] ?? null;
        return $v === null ? null : (string) $v;
    }

    public function bodyParam(string $name): mixed
    {
        return $this->body[$name] ?? null;
    }
}
