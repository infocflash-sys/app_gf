import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/portal_api.dart';
import 'screens/boot_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'util/nav.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  // Si el servidor cierra la sesión (cuenta desactivada, clave cambiada), se vuelve al login con el motivo.
  portal.sessionEnded.addListener(() {
    final msg = portal.sessionEnded.value;
    if (msg == null) return;
    navigatorKey.currentState?.pushAndRemoveUntil(fadeRoute(LoginScreen(notice: msg)), (_) => false);
  });
  runApp(const GrupoFlashApp());
}

class GrupoFlashApp extends StatelessWidget {
  const GrupoFlashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeController,
      builder: (_, mode, _) => MaterialApp(
        title: 'Portal Flash Clientes',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 400),
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
            child: child!,
          );
        },
        home: const BootScreen(),
      ),
    );
  }
}
