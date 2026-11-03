import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/portal_api.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/live_tracking_panel.dart';
import '../widgets/photo_backdrop.dart';
import '../widgets/status_chip.dart';
import '../widgets/timeline.dart';

/// Acceso sin cuenta para quien recibe el envío: busca una única pieza por su nº de
/// seguimiento exacto y muestra su estado y mapa en vivo, igual que vería un cliente
/// logueado para esa pieza puntual (sin fotos/firma/PDF: eso sigue siendo solo para clientes).
class GuestTrackingScreen extends StatefulWidget {
  const GuestTrackingScreen({super.key});

  @override
  State<GuestTrackingScreen> createState() => _GuestTrackingScreenState();
}

class _GuestTrackingScreenState extends State<GuestTrackingScreen> {
  final _barcode = TextEditingController();
  bool _loading = false;
  String? _error;
  PieceDetail? _detail;
  LiveTracking? _live;
  bool _mapOpen = true;

  @override
  void dispose() {
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final barcode = _barcode.text.trim();
    if (barcode.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await portal.publicDetail(barcode);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _mapOpen = true;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _otraPieza() {
    setState(() {
      _detail = null;
      _live = null;
      _error = null;
      _barcode.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: Brand.black,
        body: d == null ? SafeArea(child: _buscador(context)) : _resultado(context, d),
      ),
    );
  }

  Widget _buscador(BuildContext context) {
    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
        ),
      ),
      Expanded(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.packageSearch, size: 52, color: Colors.white.withValues(alpha: 0.9))
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOutBack),
              const SizedBox(height: 28),
              GlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Seguí tu envío',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Ingresá tu nº de seguimiento, sin necesidad de una cuenta',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _barcode,
                    enabled: !_loading,
                    autocorrect: false,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _buscar(),
                    decoration: const InputDecoration(
                        labelText: 'Nº de seguimiento', prefixIcon: Icon(LucideIcons.scanBarcode)),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    alignment: Alignment.topCenter,
                    child: _error == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(LucideIcons.circleAlert, size: 16, color: Color(0xFFFF7A7F)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style:
                                        const TextStyle(color: Color(0xFFFF7A7F), fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _loading ? null : _buscar,
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.navy),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _loading
                          ? const SizedBox(
                              key: ValueKey('l'),
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Brand.navy))
                          : const Text('Buscar', key: ValueKey('t')),
                    ),
                  ),
                ]),
              ).animate().fadeIn(delay: 150.ms, duration: 500.ms).slideY(begin: 0.08, end: 0),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _resultado(BuildContext context, PieceDetail d) {
    final p = d.piece;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Stack(children: [
        CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Brand.navy, Brand.black]),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  IconButton(onPressed: _otraPieza, icon: const Icon(LucideIcons.arrowLeft, color: Colors.white)),
                  const Spacer(),
                  if (p.enVivo) _LiveChip(open: _mapOpen, onTap: () => setState(() => _mapOpen = !_mapOpen)),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nº de seguimiento',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(p.tracking,
                          maxLines: 1,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    ),
                    const SizedBox(height: 14),
                    Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      if (p.estado.isNotEmpty) StatusChip(label: p.estado, definitivo: p.definitivo),
                      if (p.actualizado != null)
                        Text('Act. ${fmtAgo(p.actualizado!)}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                      if (_live?.inicioRecorrido != null)
                        Text('Inicio de Recorrido a las ${fmtTime(_live!.inicioRecorrido!)}',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          sliver: SliverList.list(children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: (_mapOpen && p.enVivo)
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: LiveTrackingPanel(
                        fetch: () => portal.publicTracking(p.tracking),
                        onUpdate: (lt) => setState(() => _live = lt),
                        pieceId: p.id,
                        tracking: p.tracking,
                        destinatario: p.destinatario,
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
                  _Row(LucideIcons.userRound, 'Destinatario', p.destinatario),
                  if (d.domicilio.isNotEmpty || p.localidad.isNotEmpty)
                    _Row(LucideIcons.mapPin, 'Entrega en',
                        [d.domicilio, p.localidad].where((s) => s.isNotEmpty).join('\n')),
                  _Row(LucideIcons.boxes, 'Bultos', '${d.bultos}', last: true),
                ]),
              ),
            ),
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
                    // sin fotos/firma acá: esa parte sigue siendo solo para clientes con cuenta.
                    : TrackingTimeline(
                        pieceId: p.id,
                        events: [
                          for (final e in d.eventos)
                            TrackEvent(
                                id: e.id, estado: e.estado, definitivo: e.definitivo, fecha: e.fecha,
                                foto: false, firma: false),
                        ],
                        onOpenImage: (_, _) {},
                      ),
              ),
            ),
          ]),
        ),
        ]),
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
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: green, shape: BoxShape.circle))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fade(begin: 0.3, end: 1, duration: 800.ms),
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
