import 'package:flutter/material.dart';

/// Transición de fundido entre pantallas.
Route<T> fadeRoute<T>(Widget page, {int ms = 450}) => PageRouteBuilder<T>(
      transitionDuration: Duration(milliseconds: ms),
      reverseTransitionDuration: Duration(milliseconds: ms),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    );
