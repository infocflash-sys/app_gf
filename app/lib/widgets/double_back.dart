import 'package:flutter/material.dart';

import '../util/app_channel.dart';

/// En la pantalla raíz, el botón "atrás" no cierra la app: avisa y pide tocarlo dos veces seguidas,
/// y entonces la MINIMIZA (queda en segundo plano y al volver está en el mismo punto).
class DoubleBackToMinimize extends StatefulWidget {
  const DoubleBackToMinimize({
    super.key,
    required this.child,
    this.enabled = true,
    this.onBack,
    this.window = const Duration(seconds: 2),
    this.clock = DateTime.now,
  });

  final Widget child;

  /// false si la pantalla no es la raíz (ahí "atrás" vuelve a la anterior como siempre).
  final bool enabled;

  /// Devuelve true si consumió el "atrás" (por ejemplo, volver a la primera pestaña).
  final bool Function()? onBack;

  final Duration window;

  /// Reloj (inyectable para poder probar el tiempo entre toques).
  final DateTime Function() clock;

  @override
  State<DoubleBackToMinimize> createState() => _DoubleBackToMinimizeState();
}

class _DoubleBackToMinimizeState extends State<DoubleBackToMinimize> {
  DateTime? _last;

  void _handle() {
    if (widget.onBack?.call() ?? false) return;
    final now = widget.clock();
    final messenger = ScaffoldMessenger.of(context);
    if (_last != null && now.difference(_last!) < widget.window) {
      _last = null;
      messenger.hideCurrentSnackBar();
      minimizeApp();
      return;
    }
    _last = now;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Presioná de nuevo para minimizar la app'),
          duration: widget.window,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        ),
      );
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.enabled,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handle();
        },
        child: widget.child,
      );
}
