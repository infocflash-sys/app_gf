import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/portal_api.dart';
import '../theme/app_theme.dart';
import '../util/nav.dart';
import '../widgets/brand_logo.dart';
import '../widgets/photo_backdrop.dart';
import 'home_shell.dart';

/// "Bienvenido" + nombre del cliente: aparece, se sostiene un instante y se desvanece hacia la app.
class GreetingScreen extends StatefulWidget {
  const GreetingScreen({super.key, required this.cliente});
  final String cliente;

  @override
  State<GreetingScreen> createState() => _GreetingScreenState();
}

class _GreetingScreenState extends State<GreetingScreen> {
  bool _left = false;

  @override
  void initState() {
    super.initState();
    portal.markGreeted();
    Future.delayed(const Duration(milliseconds: 2500), _next);
  }

  void _next() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(fadeRoute(const HomeShell(), ms: 600));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _next, // tocar para saltar
        child: PhotoBackdrop(
          blur: 9,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BrandLogo(size: 44, showText: false),
                const SizedBox(height: 28),
                Text('Bienvenido',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 20,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Text(widget.cliente,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
              ])
                  .animate()
                  .fadeIn(duration: 700.ms, curve: Curves.easeOut)
                  .slideY(begin: 0.12, end: 0, duration: 700.ms, curve: Curves.easeOutCubic)
                  .then(delay: 1000.ms)
                  .fadeOut(duration: 600.ms)
                  .slideY(begin: 0, end: -0.06, duration: 600.ms),
            ),
          ),
        ),
      ),
    );
  }
}
