<?php

declare(strict_types=1);

namespace App\Test;

use App\Auth;
use PHPUnit\Framework\TestCase;

final class AuthTest extends TestCase
{
    private static function hashOf(string $pw, string $salt): string
    {
        return $salt . substr(sha1($salt . $pw), 0, -10);
    }

    public function testIonAuthVerifyAceptaLaClaveCorrectaYRechazaOtras(): void
    {
        $h = self::hashOf('abcd1234', '48781a2b3c');
        $this->assertSame(40, strlen($h));
        $this->assertTrue(Auth::ionAuthVerify('abcd1234', $h));
        $this->assertFalse(Auth::ionAuthVerify('abcd1235', $h));
        $this->assertFalse(Auth::ionAuthVerify('', $h));
        $this->assertFalse(Auth::ionAuthVerify('abcd1234', 'corto'));
        $this->assertFalse(Auth::ionAuthVerify('abcd1234', null));
    }

    public function testWelcomeNameUnClienteUsaSuNombreVariosUsanElNombreDelUsuario(): void
    {
        $user = ['username' => 'GRUPOCEL', 'nombre' => 'Ana ', 'apellido' => ' Pérez '];
        $this->assertSame('CELSUR SA', Auth::welcomeName([['nombre' => 'CELSUR SA']], $user));
        $this->assertSame(
            'Ana Pérez',
            Auth::welcomeName([['nombre' => 'CELSUR SA'], ['nombre' => 'CELSUR LOGISTICA']], $user),
        );
        // sin nombre cargado se usa el usuario
        $this->assertSame(
            'GRUPOCEL',
            Auth::welcomeName(
                [['nombre' => 'A'], ['nombre' => 'B']],
                ['username' => 'GRUPOCEL', 'nombre' => ' ', 'apellido' => null],
            ),
        );
    }
}
