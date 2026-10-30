import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grupo_flash_portal/data/models.dart';
import 'package:grupo_flash_portal/data/portal_api.dart';
import 'package:grupo_flash_portal/widgets/live_tracking_panel.dart';
import 'package:latlong2/latlong.dart';

Widget host(Future<LiveTracking> Function() fetch) => MaterialApp(
      home: Scaffold(
        body: Center(child: LiveTrackingPanel(fetch: fetch, showMap: false, interval: const Duration(hours: 1))),
      ),
    );

LiveTracking tr({bool activo = true, bool? sinSenal, String tipo = 'ENTREGA', DateTime? fecha}) => LiveTracking(
      activo: activo,
      recorrido: 49806,
      tipo: tipo,
      destino: const LatLng(-24.19, -65.30),
      vehiculo: sinSenal == null
          ? null
          : VehiclePosition(point: const LatLng(-24.2, -65.29), fecha: fecha ?? DateTime.now(), sinSenal: sinSenal),
    );

void main() {
  testWidgets('con señal: "Tu pieza está en camino" y la antigüedad', (t) async {
    await t.pumpWidget(host(() async => tr(sinSenal: false, fecha: DateTime.now().subtract(const Duration(seconds: 20)))));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Tu pieza está en camino'), findsOneWidget);
    expect(find.textContaining('Última señal hace'), findsOneWidget);
    expect(find.text('EN VIVO'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('sin señal reciente: avisa y muestra la última ubicación conocida', (t) async {
    await t.pumpWidget(host(() async => tr(sinSenal: true, fecha: DateTime.now().subtract(const Duration(minutes: 33)))));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Sin señal reciente'), findsOneWidget);
    expect(find.textContaining('hace 33 min'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('recorrido abierto pero sin ningún punto GPS', (t) async {
    await t.pumpWidget(host(() async => tr()));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('Sin señal del vehículo por ahora'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('seguimiento terminado: lo informa y deja de actualizar', (t) async {
    var llamadas = 0;
    await t.pumpWidget(host(() async {
      llamadas++;
      return const LiveTracking(activo: false);
    }));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('El seguimiento en vivo ya no está disponible'), findsOneWidget);
    expect(llamadas, 1);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('error de red: lo informa sin romperse', (t) async {
    await t.pumpWidget(host(() async => throw ApiException('NETWORK', 'Sin conexión.')));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('No pudimos cargar la ubicación'), findsOneWidget);
    expect(find.text('Sin conexión.'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  test('LiveTracking.fromJson interpreta vehículo, destino y tipo', () {
    final l = LiveTracking.fromJson({
      'activo': true,
      'recorrido': 49806,
      'tipo': 'ENTREGA',
      'destino': {'lat': -24.19, 'lng': -65.30},
      'vehiculo': {'lat': -24.2, 'lng': -65.29, 'fecha': '2026-10-29T15:09:46-03:00', 'segundos': 684, 'sinSenal': false},
    });
    expect(l.activo, isTrue);
    expect(l.esRetiro, isFalse);
    expect(l.destino!.latitude, -24.19);
    expect(l.vehiculo!.sinSenal, isFalse);
    expect(LiveTracking.fromJson({'activo': false}).vehiculo, isNull);
    expect(Piece.fromJson({'id': 1, 'enVivo': true}).enVivo, isTrue);
    expect(Piece.fromJson({'id': 1}).enVivo, isFalse);
  });
}
