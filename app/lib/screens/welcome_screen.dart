import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import '../util/nav.dart';
import '../widgets/brand_logo.dart';
import '../widgets/double_back.dart';
import '../widgets/photo_backdrop.dart';
import '../widgets/theme_toggle.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DoubleBackToMinimize(enabled: !Navigator.of(context).canPop(), child: _page(context));

  Widget _page(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.black,
      body: PhotoBackdrop(
        child: Stack(children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, _) => CustomPaint(painter: _RoutePainter(_ctrl.value)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 12, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const BrandLogo(size: 42),
                  const Spacer(),
                  const ThemeToggleButton(color: Colors.white),
                ]).animate().fadeIn(duration: 500.ms),
                const Spacer(flex: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.radio, size: 14, color: Brand.accent),
                    SizedBox(width: 8),
                    Text('Portal Clientes',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.4)),
                  ]),
                ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.3, end: 0),
                const SizedBox(height: 18),
                Text(
                  'Tus envíos,\nsiempre a la vista.',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: -1,
                      ),
                )
                    .animate()
                    .fadeIn(delay: 250.ms, duration: 600.ms)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 14),
                Text(
                  'Consultá el estado, el seguimiento, las fotos de entrega y '
                  'la documentación de tus piezas.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.76), fontSize: 15.5, height: 1.4),
                ).animate().fadeIn(delay: 400.ms, duration: 600.ms),
                const SizedBox(height: 22),
                Wrap(spacing: 8, runSpacing: 8, children: const [
                  _Feature(LucideIcons.packageSearch, 'Estado de piezas'),
                  _Feature(LucideIcons.camera, 'Fotos y firmas'),
                  _Feature(LucideIcons.fileText, 'Documentación'),
                ]).animate().fadeIn(delay: 550.ms, duration: 600.ms),
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(fadeRoute(const LoginScreen())),
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.navy),
                    icon: const Icon(LucideIcons.logIn),
                    label: const Text('Ingresar'),
                  ),
                )
                    .animate()
                    .fadeIn(delay: 700.ms, duration: 600.ms)
                    .slideY(begin: 0.25, end: 0, curve: Curves.easeOutCubic),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Brand.accent),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Curva de ruta con un punto luminoso que la recorre.
class _RoutePainter extends CustomPainter {
  _RoutePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(-20, h * 0.30)
      ..cubicTo(w * 0.25, h * 0.12, w * 0.40, h * 0.50, w * 0.65, h * 0.30)
      ..cubicTo(w * 0.85, h * 0.14, w * 0.95, h * 0.22, w + 20, h * 0.16);

    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.12));

    final metric = path.computeMetrics().first;
    final len = metric.length;
    final head = len * t;
    final tail = math.max(0.0, head - len * 0.25);
    canvas.drawPath(
      metric.extractPath(tail, head),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Brand.accent.withValues(alpha: 0.9),
    );
    final pos = metric.getTangentForOffset(head)?.position;
    if (pos != null) {
      canvas.drawCircle(pos, 16, Paint()..color = Brand.accent.withValues(alpha: 0.18));
      canvas.drawCircle(pos, 6, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.t != t;
}
