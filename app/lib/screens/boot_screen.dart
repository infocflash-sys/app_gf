import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/portal_api.dart';
import '../data/resume.dart';
import '../theme/app_theme.dart';
import '../util/nav.dart';
import '../widgets/brand_logo.dart';
import 'greeting_screen.dart';
import 'home_shell.dart';
import 'welcome_screen.dart';

/// Primera pantalla: restaura la sesión guardada (si existe) y valida que la cuenta siga activa.
class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    try {
      final p = await portal.restore();
      if (!mounted) return;
      if (p == null) {
        Navigator.of(context).pushReplacement(fadeRoute(const WelcomeScreen()));
        return;
      }
      // saludo de bienvenida la primera vez que se abre la app en el día
      final greet = await portal.shouldGreetToday();
      // si Android cerró la app en segundo plano, se retoma la pieza (y el mapa) que se estaba viendo
      final resume = await ResumeStore.load();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        fadeRoute(greet ? GreetingScreen(cliente: p.cliente) : HomeShell(resume: resume)),
      );
    } on ApiException catch (e) {
      // si la cuenta fue desactivada, la navegación a login la hace la app raíz
      if (!mounted || portal.sessionEnded.value != null) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Brand.navy, Brand.black],
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandLogo(size: 56),
            const SizedBox(height: 36),
            if (_error == null)
              const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white70))
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Text(_error!,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _start,
                style: FilledButton.styleFrom(
                    minimumSize: const Size(160, 48),
                    backgroundColor: Colors.white,
                    foregroundColor: Brand.navy),
                icon: const Icon(LucideIcons.refreshCw, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
