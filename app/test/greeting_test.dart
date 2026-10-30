import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grupo_flash_portal/screens/greeting_screen.dart';
import 'package:grupo_flash_portal/screens/home_shell.dart';

void main() {
  testWidgets('el saludo muestra el nombre del CLIENTE y se desvanece hacia la app', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GreetingScreen(cliente: 'CELSUR LOGISTICA SA')));
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('Bienvenido'), findsOneWidget);
    expect(find.text('CELSUR LOGISTICA SA'), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);

    // tras ~2,5 s pasa solo a la pantalla principal (con su transición de fundido)
    await tester.pump(const Duration(milliseconds: 2000));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Bienvenido'), findsNothing);
  });

  testWidgets('tocar el saludo lo saltea', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GreetingScreen(cliente: 'ACME SA')));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tapAt(tester.getCenter(find.byType(Scaffold)));
    await tester.pump(); // la ruta se inserta en este fotograma
    await tester.pump(const Duration(milliseconds: 800)); // y completa su fundido
    expect(find.byType(HomeShell), findsOneWidget);
    // deja correr el temporizador original (no debe volver a navegar)
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(HomeShell), findsOneWidget);
  });
}
