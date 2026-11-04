<?php

declare(strict_types=1);

namespace App\Test;

use App\Tracking;
use PHPUnit\Framework\TestCase;

final class TrackingTest extends TestCase
{
    // `trackingOf()` ahora siempre consulta `ruteo` (recorrido abierto) antes de mirar el estado_id
    // -ya no hay un gate que evite la consulta-, así que ya no se puede probar sin una DB real;
    // queda cubierto por las pruebas manuales de lectura hechas al validar la lógica con datos reales.

    private static function detalle(): array
    {
        return [
            ['tipo' => 'ORIGEN/DESTINO', 'latitud' => '-24.2064098', 'longitud' => '-65.2832773', 'orden_recorrido' => 1],
            ['tipo' => 'RETIRO', 'latitud' => '-24.1973729', 'longitud' => '-65.3100605', 'orden_recorrido' => 2],
            ['tipo' => 'ENTREGA', 'latitud' => '-24.1875629', 'longitud' => '-65.2944976', 'orden_recorrido' => 3],
        ];
    }

    public function testPickStopLaEntregaPorDefectoElRetiroSiLaPiezaEsperaRetiro(): void
    {
        $detalle = self::detalle();
        $this->assertSame('ENTREGA', Tracking::pickStop($detalle, 'En distribucion')['tipo']);
        $this->assertSame('RETIRO', Tracking::pickStop($detalle, 'Pendiente de Retiro')['tipo']);
        $this->assertSame('RETIRO', Tracking::pickStop([$detalle[1]], 'En distribucion')['tipo']); // solo hay retiro
        $this->assertNull(Tracking::pickStop([$detalle[0]], 'x')); // el depósito no es un punto de la pieza
        $this->assertNull(Tracking::pickStop([], 'x'));
    }

    public function testPickStopConvierteLasCoordenadasDeTextoYDescartaLasInvalidas(): void
    {
        $s = Tracking::pickStop(self::detalle(), 'En distribucion');
        $this->assertIsFloat($s['lat']);
        $this->assertLessThan(1e-9, abs($s['lat'] - -24.1875629));
        $this->assertNull(Tracking::pickStop([['tipo' => 'ENTREGA', 'latitud' => '0', 'longitud' => '0', 'orden_recorrido' => 1]], 'x'));
        $this->assertNull(Tracking::pickStop([['tipo' => 'ENTREGA', 'latitud' => 'abc', 'longitud' => '1', 'orden_recorrido' => 1]], 'x'));
    }

    public function testDescribePositionAntiguedadYSinSenalALos15Minutos(): void
    {
        $now = strtotime('2026-10-29T15:00:00-03:00');
        $fresh = Tracking::describePosition(['lat' => 1, 'lng' => 2, 'fechaTs' => $now - 20, 'fechaDb' => '2026-10-29 14:59:40'], $now);
        $this->assertSame(20, $fresh['segundos']);
        $this->assertFalse($fresh['sinSenal']);
        $this->assertSame('2026-10-29T14:59:40-03:00', $fresh['fecha']);

        $old = Tracking::describePosition(['lat' => 1, 'lng' => 2, 'fechaTs' => $now - 16 * 60, 'fechaDb' => '2026-10-29 14:44:00'], $now);
        $this->assertTrue($old['sinSenal']);

        $this->assertNull(Tracking::describePosition(null, $now));
    }
}
