import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grupo_flash_portal/data/resume.dart';
import 'package:grupo_flash_portal/widgets/double_back.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.grupoflash.portal/app');
const _aviso = 'Presioná de nuevo para minimizar la app';

Widget _app({bool Function()? onBack, DateTime Function()? clock}) => MaterialApp(
      home: DoubleBackToMinimize(
        onBack: onBack,
        clock: clock ?? DateTime.now,
        child: const Scaffold(body: Text('raiz')),
      ),
    );

void main() {
  testWidgets('"atrás" una vez avisa; dos veces seguidas minimiza la app', (t) async {
    var minimizadas = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'minimize') minimizadas++;
      return true;
    });
    await t.pumpWidget(_app());

    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text(_aviso), findsOneWidget);
    expect(minimizadas, 0);

    await t.binding.handlePopRoute();
    await t.pump();
    expect(minimizadas, 1);
    expect(find.text(_aviso), findsNothing);
  });

  testWidgets('si pasan más de 2 segundos, vuelve a avisar en vez de minimizar', (t) async {
    var minimizadas = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'minimize') minimizadas++;
      return true;
    });
    var ahora = DateTime(2026, 10, 29, 12);
    await t.pumpWidget(_app(clock: () => ahora));

    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 2600));
    ahora = ahora.add(const Duration(milliseconds: 2600)); // pasó más que la ventana de 2 s
    await t.binding.handlePopRoute();
    await t.pump();
    expect(minimizadas, 0);
    expect(find.text(_aviso), findsOneWidget);
    await t.pump(const Duration(seconds: 3)); // deja correr el temporizador del aviso
  });

  testWidgets('si la pantalla consume el "atrás" (volver de pestaña), no avisa ni minimiza', (t) async {
    var minimizadas = 0;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      if (call.method == 'minimize') minimizadas++;
      return true;
    });
    await t.pumpWidget(_app(onBack: () => true));
    await t.binding.handlePopRoute();
    await t.pump();
    expect(find.text(_aviso), findsNothing);
    expect(minimizadas, 0);
  });

  group('ResumeStore', () {
    test('guarda y recupera la pieza y el mapa abierto', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await ResumeStore.load(), isNull);
      await ResumeStore.save(213879, mapOpen: true);
      final r = await ResumeStore.load();
      expect(r!.pieceId, 213879);
      expect(r.mapOpen, isTrue);
      await ResumeStore.clear();
      expect(await ResumeStore.load(), isNull);
    });

    test('no retoma si pasaron más de 30 minutos', () async {
      final viejo = DateTime.now().subtract(const Duration(minutes: 45)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({'resume_piece': 5, 'resume_map': true, 'resume_at': viejo});
      expect(await ResumeStore.load(), isNull);
      final reciente = DateTime.now().subtract(const Duration(minutes: 10)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({'resume_piece': 5, 'resume_map': false, 'resume_at': reciente});
      expect((await ResumeStore.load())!.pieceId, 5);
    });
  });
}
