import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/portal_api.dart';
import '../widgets/live_tracking_panel.dart';

/// Mapa "Sigue en tiempo real" a pantalla completa. El botón de arriba a la izquierda
/// (o el "atrás" del teléfono) vuelve al detalle de la pieza.
class LiveTrackingScreen extends StatelessWidget {
  const LiveTrackingScreen({super.key, required this.pieceId});
  final int pieceId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: LiveTrackingPanel(fullScreen: true, fetch: () => portal.tracking(pieceId)),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: IconButton.filled(
              tooltip: 'Volver',
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                elevation: 4,
                shadowColor: Colors.black45,
                minimumSize: const Size(46, 46),
              ),
              icon: const Icon(LucideIcons.arrowLeft),
            ),
          ),
        ),
      ]),
    );
  }
}
