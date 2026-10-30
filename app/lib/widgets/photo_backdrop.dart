import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Fondo de bienvenida/login: foto de logística desenfocada bajo un degradé
/// marino a negro, para dar lejanía y mantener el contraste con el contenido.
class PhotoBackdrop extends StatelessWidget {
  const PhotoBackdrop({super.key, this.blur = 5, this.child});
  final double blur;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    // sobre este fondo oscuro la barra de estado lleva íconos claros
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: _content(),
    );
  }

  Widget _content() {
    return Stack(fit: StackFit.expand, children: [
      const ColoredBox(color: Brand.black),
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.clamp),
        child: Image.asset('assets/images/welcome_bg.jpg', fit: BoxFit.cover, alignment: Alignment.center),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Brand.navy.withValues(alpha: 0.38),
              Brand.navyDeep.withValues(alpha: 0.58),
              Brand.black.withValues(alpha: 0.92),
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
      ),
      ?child,
    ]);
  }
}

/// Tarjeta de vidrio esmerilado para formularios sobre el fondo con foto.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding = const EdgeInsets.all(22)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: child,
        ),
      ),
    );
  }
}
