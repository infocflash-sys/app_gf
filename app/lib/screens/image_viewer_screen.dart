import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../util/format.dart';
import '../widgets/auth_image.dart';

/// Foto o firma a pantalla completa, con zoom.
class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.pieceId, required this.event, required this.kind});
  final int pieceId;
  final TrackEvent event;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final title = kind == 'foto' ? 'Foto de gestión' : 'Firma';
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Hero(
                tag: 'img-$pieceId-${event.id}-$kind',
                child: AuthImage(pieceId: pieceId, eventId: event.id, kind: kind, full: true, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.x),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '$title · ${event.estado}${event.fecha == null ? '' : '\n${fmtDateTime(event.fecha!)}'}',
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
