import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/portal_api.dart';

/// Visor del PDF asociado a la pieza. Se descarga con la sesión y se abre en la app.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.pieceId});
  final int pieceId;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  late Future<File> _file = portal.pdfFile(widget.pieceId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documento')),
      body: FutureBuilder<File>(
        future: _file,
        builder: (context, snap) {
          if (snap.hasData) return PdfViewer.file(snap.data!.path);
          if (snap.hasError) {
            final msg = snap.error is ApiException ? (snap.error as ApiException).message : 'No se pudo abrir el documento.';
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(LucideIcons.fileX, size: 48),
                const SizedBox(height: 12),
                Text(msg),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _file = portal.pdfFile(widget.pieceId)),
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                  label: const Text('Reintentar'),
                ),
              ]),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
