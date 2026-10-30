import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/portal_api.dart';

/// Imagen de un evento (foto o firma). Se pide con la sesión, nunca por URL pública.
class AuthImage extends StatefulWidget {
  const AuthImage({
    super.key,
    required this.pieceId,
    required this.eventId,
    required this.kind,
    this.full = false,
    this.fit = BoxFit.cover,
  });
  final int pieceId;
  final int eventId;
  final String kind; // 'foto' | 'firma'
  final bool full;
  final BoxFit fit;

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  late Future<Uint8List> _future = _load();

  Future<Uint8List> _load() =>
      portal.eventImage(widget.pieceId, widget.eventId, widget.kind, full: widget.full);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(snap.data!, fit: widget.fit, gaplessPlayback: true)
              ;
        }
        if (snap.hasError) {
          return InkWell(
            onTap: () => setState(() => _future = _load()),
            child: Container(
              color: cs.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(LucideIcons.refreshCw, size: 20, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(height: 6),
                Text('Reintentar',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
              ]),
            ),
          );
        }
        return Container(
          color: cs.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
        );
      },
    );
  }
}
