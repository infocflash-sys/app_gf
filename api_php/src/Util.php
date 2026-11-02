<?php

declare(strict_types=1);

namespace App;

final class Util
{
    /** Fecha de la DB ("YYYY-MM-DD HH:mm:ss", hora de Argentina) a ISO con offset. */
    public static function toIso(?string $s): ?string
    {
        if ($s === null || $s === '') {
            return null;
        }
        return str_replace(' ', 'T', $s) . '-03:00';
    }

    /** Nombre de archivo seguro: evita rutas relativas y caracteres raros. */
    public static function safeName(?string $name, ?array $extensions = null): ?string
    {
        if ($name === null) {
            return null;
        }
        $n = trim($name);
        if (!preg_match('/^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,100}$/', $n) || str_contains($n, '..')) {
            return null;
        }
        if ($extensions !== null) {
            $ext = strtolower(pathinfo($n, PATHINFO_EXTENSION));
            if (!in_array($ext, $extensions, true)) {
                return null;
            }
        }
        return $n;
    }

    /**
     * Quita eventos repetidos: mismo estado dentro del mismo minuto.
     * Espera la lista ordenada del más nuevo al más viejo (arrays asociativos con
     * estadoId, fecha, foto, firma, fotoEventoId).
     *
     * @param array<int, array<string, mixed>> $events
     * @return array<int, array<string, mixed>>
     */
    public static function dedupeEvents(array $events): array
    {
        $out = [];
        foreach ($events as $e) {
            $prev = $out ? array_key_last($out) : null;
            $same = false;
            if ($prev !== null) {
                $p = $out[$prev];
                $same = $p['estadoId'] === $e['estadoId']
                    && abs(strtotime((string) $p['fecha']) - strtotime((string) $e['fecha'])) < 60;
            }
            if ($same) {
                $out[$prev]['foto'] = $out[$prev]['foto'] || $e['foto'];
                $out[$prev]['firma'] = $out[$prev]['firma'] || $e['firma'];
                $out[$prev]['fotoEventoId'] ??= $e['fotoEventoId'];
                continue;
            }
            $out[] = $e;
        }
        return $out;
    }
}
