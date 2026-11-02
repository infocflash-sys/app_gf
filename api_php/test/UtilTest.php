<?php

declare(strict_types=1);

namespace App\Test;

use App\Util;
use PHPUnit\Framework\TestCase;

final class UtilTest extends TestCase
{
    public function testSafeNameBloqueaRutasYExtensionesNoPermitidas(): void
    {
        $this->assertSame('1793205049206.jpg', Util::safeName('1793205049206.jpg', ['jpg']));
        $this->assertSame('firma_1793231631837.jpg', Util::safeName('firma_1793231631837.jpg', ['jpg']));
        $this->assertSame('191617-1.pdf', Util::safeName('191617-1.pdf', ['pdf']));
        $this->assertNull(Util::safeName('../../etc/passwd', ['jpg']));
        $this->assertNull(Util::safeName('a/b.jpg', ['jpg']));
        $this->assertNull(Util::safeName('a..b.jpg', ['jpg']));
        $this->assertNull(Util::safeName('foto.exe', ['jpg']));
        $this->assertNull(Util::safeName('', ['jpg']));
        $this->assertNull(Util::safeName(null, ['jpg']));
    }

    public function testDedupeEventsUneRepetidosDelMismoMinutoYConservaLaFoto(): void
    {
        $ev = [
            ['id' => 3, 'estadoId' => 13, 'fecha' => '2026-08-07T16:03:00-03:00', 'foto' => true, 'firma' => false, 'fotoEventoId' => 3],
            ['id' => 2, 'estadoId' => 79, 'fecha' => '2026-08-07T01:53:10-03:00', 'foto' => false, 'firma' => false, 'fotoEventoId' => 2],
            ['id' => 1, 'estadoId' => 79, 'fecha' => '2026-08-07T01:53:40-03:00', 'foto' => false, 'firma' => false, 'fotoEventoId' => 1],
            ['id' => 0, 'estadoId' => 79, 'fecha' => '2026-08-06T01:53:40-03:00', 'foto' => false, 'firma' => false, 'fotoEventoId' => 0],
        ];
        $out = Util::dedupeEvents($ev);
        $this->assertCount(3, $out);
        $this->assertTrue($out[0]['foto']);
    }

    public function testToIsoAgregaLaZonaHorariaDeArgentina(): void
    {
        $this->assertSame('2026-08-07T16:03:00-03:00', Util::toIso('2026-08-07 16:03:00'));
        $this->assertNull(Util::toIso(null));
    }
}
