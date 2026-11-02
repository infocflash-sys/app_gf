import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/portal_api.dart';
import '../data/resume.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/live_tracking_panel.dart';
import '../widgets/status_chip.dart';
import '../widgets/timeline.dart';
import 'image_viewer_screen.dart';
import 'live_tracking_screen.dart';
import 'pdf_viewer_screen.dart';

class PieceDetailScreen extends StatefulWidget {
  const PieceDetailScreen({super.key, required this.piece, this.initialMapOpen = false});

  /// Abre la pieza solo por su id (por ejemplo, al retomar donde se había quedado).
  PieceDetailScreen.byId(int id, {super.key, bool mapOpen = false})
      : piece = Piece(
          id: id,
          tracking: '…',
          destinatario: '',
          localidad: '',
          cantidad: 1,
          estado: '',
          definitivo: false,
          fecha: null,
        ),
        initialMapOpen = mapOpen;

  final Piece piece;
  final bool initialMapOpen;

  @override
  State<PieceDetailScreen> createState() => _PieceDetailScreenState();
}

class _PieceDetailScreenState extends State<PieceDetailScreen> {
  PieceDetail? _detail;
  String? _error;
  late bool _mapOpen = widget.initialMapOpen;
  LiveTracking? _live;

  @override
  void initState() {
    super.initState();
    ResumeStore.save(widget.piece.id, mapOpen: _mapOpen); // por si Android cierra la app en segundo plano
    _load();
  }

  void _toggleMap() {
    setState(() => _mapOpen = !_mapOpen);
    ResumeStore.save(widget.piece.id, mapOpen: _mapOpen);
  }

  /// Mapa a pantalla completa (con botón de retroceso). El mapa chico se cierra mientras tanto
  /// para no consultar dos veces, y se vuelve a abrir al regresar.
  Future<void> _expandMap() async {
    setState(() => _mapOpen = false);
    final d = _detail;
    await Navigator.of(context).push(fadeRoute(
      LiveTrackingScreen(
        pieceId: widget.piece.id,
        tracking: d?.piece.tracking ?? widget.piece.tracking,
        destinatario: d?.piece.destinatario ?? widget.piece.destinatario,
        domicilio: d?.domicilio,
      ),
      ms: 280,
    ));
    if (mounted) setState(() => _mapOpen = true);
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await portal.detail(widget.piece.id);
      if (mounted) setState(() => _detail = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = widget.piece;
    final d = _detail;
    return PopScope(
      // al salir de la pieza con "atrás" ya no hay nada que retomar
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) ResumeStore.clear();
      },
      child: Scaffold(
      body: _TopBar(child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: _Header(
            piece: d?.piece ?? p,
            enVivo: d?.piece.enVivo ?? p.enVivo,
            mapOpen: _mapOpen,
            onToggleMap: _toggleMap,
            inicioRecorrido: _live?.inicioRecorrido,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          sliver: d == null
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : Column(children: [
                              Icon(LucideIcons.wifiOff, size: 44, color: cs.onSurface.withValues(alpha: 0.35)),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 14),
                              FilledButton.tonalIcon(
                                onPressed: _load,
                                icon: const Icon(LucideIcons.refreshCw, size: 18),
                                label: const Text('Reintentar'),
                              ),
                            ]),
                    ),
                  ),
                )
              : SliverList.list(
                  children: [
                    // mapa desplegable "Sigue en tiempo real"
                    AnimatedSize(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: (_mapOpen && d.piece.enVivo)
                          ? Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: LiveTrackingPanel(
                                fetch: () => portal.tracking(p.id),
                                onExpand: _expandMap,
                                onUpdate: (lt) => setState(() => _live = lt),
                                pieceId: d.piece.id,
                                tracking: d.piece.tracking,
                                destinatario: d.piece.destinatario,
                                domicilio: d.domicilio,
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                    _Section('Datos del envío', LucideIcons.info),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          _Row(LucideIcons.scanBarcode, 'Nº', d.piece.tracking),
                          if (d.piece.remito != null) _Row(LucideIcons.fileCheck, 'Remito', d.piece.remito!),
                          _Row(LucideIcons.userRound, 'Destinatario', d.piece.destinatario),
                          if (d.domicilio.isNotEmpty || d.piece.localidad.isNotEmpty)
                            _Row(LucideIcons.mapPin, 'Entrega en',
                                [d.domicilio, d.piece.localidad].where((s) => s.isNotEmpty).join('\n')),
                          _Row(LucideIcons.boxes, 'Bultos', '${d.bultos}'),
                          if (d.pesoKg != null && d.pesoKg! > 0)
                            _Row(LucideIcons.weight, 'Peso', '${d.pesoKg!.toStringAsFixed(d.pesoKg! % 1 == 0 ? 0 : 1)} kg'),
                          if (d.piece.fecha != null)
                            _Row(LucideIcons.calendarDays, 'Ingreso', fmtDateTime(d.piece.fecha!), last: true),
                        ]),
                      ),
                    ),
                    if (d.pdf) ...[
                      const SizedBox(height: 24),
                      _Section('Documentación', LucideIcons.fileText),
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: StatusColors.novedad.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(LucideIcons.fileText, color: StatusColors.novedad, size: 22),
                          ),
                          title: const Text('Documento de la pieza', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('PDF'),
                          trailing: Icon(LucideIcons.chevronRight, size: 20, color: cs.primary),
                          onTap: () => Navigator.of(context).push(fadeRoute(PdfViewerScreen(pieceId: p.id), ms: 300)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    _Section('Seguimiento', LucideIcons.route),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: d.eventos.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.only(bottom: 18),
                                child: Text('Todavía no hay movimientos registrados.'),
                              )
                            : TrackingTimeline(
                                pieceId: p.id,
                                events: d.eventos,
                                onOpenImage: (e, kind) => Navigator.of(context).push(
                                  fadeRoute(ImageViewerScreen(pieceId: p.id, event: e, kind: kind), ms: 280),
                                ),
                              ),
                      ),
                    ),
                  ]
                      .animate(interval: 60.ms)
                      .fadeIn(duration: 360.ms)
                      .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic),
                ),
        ),
      ])),
      ),
    );
  }
}

/// La cabecera es oscura: íconos claros en la barra de estado y un fondo marino fijo
/// detrás de ella para que se lean también al desplazar el contenido.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Stack(children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top,
          child: const ColoredBox(color: Brand.navy),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.piece,
    required this.enVivo,
    required this.mapOpen,
    required this.onToggleMap,
    this.inicioRecorrido,
  });
  final Piece piece;
  final bool enVivo;
  final bool mapOpen;
  final VoidCallback onToggleMap;

  /// Primer punto GPS de hoy del cartero: cuándo salió "a la calle" con este recorrido.
  final DateTime? inicioRecorrido;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Brand.navy, Brand.black],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
              ),
              const Spacer(),
              if (enVivo) _LiveChip(open: mapOpen, onTap: onToggleMap),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nº de seguimiento',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                const SizedBox(height: 2),
                Hero(
                  tag: 'trk-${piece.id}',
                  child: Material(
                    color: Colors.transparent,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(piece.tracking,
                          maxLines: 1,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (piece.estado.isNotEmpty) StatusChip(label: piece.estado, definitivo: piece.definitivo),
                  if (piece.actualizado != null)
                    Text('Act. ${fmtAgo(piece.actualizado!)}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                  if (inicioRecorrido != null)
                    Text('Inicio de Recorrido a las ${fmtTime(inicioRecorrido!)}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Arriba a la derecha: "Sigue en tiempo real". Despliega y pliega el mapa.
class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const green = StatusColors.gestionDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          decoration: BoxDecoration(
            color: green.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: green.withValues(alpha: 0.55)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: green, shape: BoxShape.circle),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.3, end: 1, duration: 800.ms),
            const SizedBox(width: 8),
            const Text('Sigue en tiempo real',
                style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: const Duration(milliseconds: 250),
              child: const Icon(LucideIcons.chevronDown, size: 18, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.icon);
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 4),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, this.value, {this.last = false});
  final IconData icon;
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: cs.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 12),
        SizedBox(width: 92, child: Text(label, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
