import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/portal_api.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/status_chip.dart';
import '../widgets/theme_toggle.dart';
import 'piece_detail_screen.dart';

class PiecesScreen extends StatefulWidget {
  const PiecesScreen({super.key});

  @override
  State<PiecesScreen> createState() => _PiecesScreenState();
}

class _PiecesScreenState extends State<PiecesScreen> {
  final _scroll = ScrollController();
  final _items = <Piece>[];
  Resumen? _res;
  int _page = 0;
  bool _more = true;
  bool _loading = false;
  String? _error;

  String _q = '';
  bool _enCurso = true; // verde: sigue en gestión
  bool _gestionado = true; // azul: estado definitivo
  final _searchCtl = TextEditingController();
  int _dias = 30;
  bool _grid = false;
  Timer? _debounce;
  int _gen = 0; // descarta respuestas de pedidos viejos

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 420) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || !_more || _error != null)) return;
    final gen = reset ? ++_gen : _gen;
    if (reset) {
      _page = 0;
      _more = true;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await portal.pieces(page: _page + 1, q: _q, grupo: _grupo, dias: _dias);
      if (gen != _gen || !mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _page++;
        _more = page.hasMore;
        _res = page.resumen ?? _res;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (gen != _gen || !mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Ambos activos = todas. Uno solo = ese grupo. Siempre queda al menos uno activo.
  String? get _grupo => _enCurso == _gestionado ? null : (_enCurso ? 'gestion' : 'finalizadas');

  void _toggle({required bool gestionado}) {
    final en = gestionado ? _enCurso : !_enCurso;
    final ge = gestionado ? !_gestionado : _gestionado;
    if (!en && !ge) return;
    setState(() {
      _enCurso = en;
      _gestionado = ge;
    });
    _load(reset: true);
  }

  void _open(Piece p) => Navigator.of(context).push(fadeRoute(PieceDetailScreen(piece: p), ms: 380));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initialLoad = _loading && _items.isEmpty;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _header(context)),
            SliverToBoxAdapter(child: _toggles(context)),
            SliverToBoxAdapter(child: _search(context)),
            SliverToBoxAdapter(child: _filters(context)),
            if (initialLoad)
              SliverList.separated(
                itemCount: 4,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, _) => const _Skeleton(),
              )
            else if (_error != null && _items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Message(
                  icon: LucideIcons.wifiOff,
                  text: _error!,
                  action: FilledButton.tonalIcon(
                    onPressed: () => _load(reset: true),
                    icon: const Icon(LucideIcons.refreshCw, size: 18),
                    label: const Text('Reintentar'),
                  ),
                ),
              )
            else if (_items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Message(
                  icon: LucideIcons.packageSearch,
                  text: _q.isEmpty && _grupo == null
                      ? 'No hay piezas en los últimos $_dias días.'
                      : 'No hay piezas que coincidan.',
                ),
              )
            else if (_grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                sliver: SliverList.builder(
                  itemCount: _items.length + 1,
                  itemBuilder: (_, i) =>
                      i == 0 ? const _GridHeader() : _GridRow(piece: _items[i - 1], odd: i.isOdd, onTap: _open),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                sliver: SliverList.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _PieceCard(piece: _items[i], onTap: _open)
                      .animate(delay: (50 * (i % 8)).ms)
                      .fadeIn(duration: 320.ms)
                      .slideY(begin: 0.10, end: 0, curve: Curves.easeOutCubic),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: _loading && _items.isNotEmpty
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : _error != null && _items.isNotEmpty
                          ? TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(LucideIcons.refreshCw, size: 16),
                              label: const Text('Reintentar'))
                          : (!_more && _items.isNotEmpty)
                              ? Text('${_items.length} piezas',
                                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45), fontSize: 12.5))
                              : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mis piezas', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
            Text(portal.profile?.cliente ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge),
          ]),
        ),
        const ThemeToggleButton(),
      ]),
    );
  }

  Widget _toggles(BuildContext context) {
    final r = _res;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(children: [
        Expanded(
          child: _StateToggle(
            label: 'En curso',
            icon: LucideIcons.loader,
            count: r?.enGestion,
            color: StatusColors.of(context, definitivo: false),
            active: _enCurso,
            onTap: () => _toggle(gestionado: false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StateToggle(
            label: 'Gestionado',
            icon: LucideIcons.circleCheck,
            count: r?.finalizadas,
            color: StatusColors.of(context, definitivo: true),
            active: _gestionado,
            onTap: () => _toggle(gestionado: true),
          ),
        ),
      ]),
    );
  }
  Widget _search(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: TextField(
          controller: _searchCtl,
          onChanged: (v) {
            setState(() {}); // muestra u oculta el botón de borrar
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 450), () {
              _q = v;
              _load(reset: true);
            });
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar por nº, código, remito o nombre',
            prefixIcon: const Icon(LucideIcons.search),
            suffixIcon: _searchCtl.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    icon: const Icon(LucideIcons.x),
                    onPressed: () {
                      _searchCtl.clear();
                      _debounce?.cancel();
                      _q = '';
                      setState(() {});
                      _load(reset: true);
                    },
                  ),
          ),
        ),
      );

  Widget _filters(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
      child: Row(children: [
        PopupMenuButton<int>(
          tooltip: 'Período',
          initialValue: _dias,
          onSelected: (d) {
            setState(() => _dias = d);
            _load(reset: true);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 30, child: Text('Últimos 30 días')),
            PopupMenuItem(value: 90, child: Text('Últimos 90 días')),
            PopupMenuItem(value: 180, child: Text('Últimos 6 meses')),
            PopupMenuItem(value: 365, child: Text('Último año')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(LucideIcons.calendarDays, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(switch (_dias) { 30 => '30 días', 90 => '90 días', 180 => '6 meses', _ => '1 año' },
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 4),
              const Icon(LucideIcons.chevronDown, size: 16),
            ]),
          ),
        ),
        const Spacer(),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
          segments: const [
            ButtonSegment(value: false, icon: Icon(LucideIcons.layoutList, size: 18), tooltip: 'Tarjetas'),
            ButtonSegment(value: true, icon: Icon(LucideIcons.table, size: 18), tooltip: 'Tabla'),
          ],
          selected: {_grid},
          onSelectionChanged: (s) => setState(() => _grid = s.first),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }
}

/// Botón-interruptor de estado: En curso (verde) / Gestionado (azul), con su cantidad.
class _StateToggle extends StatelessWidget {
  const _StateToggle({
    required this.label,
    required this.icon,
    required this.count,
    required this.color,
    required this.active,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final int? count;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? color : cs.onSurface.withValues(alpha: 0.5);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.14) : cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? color : cs.outlineVariant, width: active ? 1.6 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 20, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: fg)),
                const SizedBox(height: 2),
                count == null
                    ? Text('—', style: TextStyle(fontSize: 12.5, color: fg))
                    : TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: count!),
                        duration: const Duration(milliseconds: 600),
                        builder: (_, v, _) => Text(' ',
                            style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.85))),
                      ),
              ]),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(active ? LucideIcons.squareCheck : LucideIcons.square,
                  key: ValueKey(active), size: 20, color: fg),
            ),
          ]),
        ),
      ),
    );
  }
}
class _PieceCard extends StatelessWidget {
  const _PieceCard({required this.piece, required this.onTap});
  final Piece piece;
  final void Function(Piece) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = StatusColors.of(context, definitivo: piece.definitivo);
    final dim = cs.onSurface.withValues(alpha: 0.6);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onTap(piece),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: tint),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // el nº de seguimiento va completo en su propia línea; el estado debajo
                  Hero(
                    tag: 'trk-${piece.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: Text(piece.tracking,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: 0.3)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    StatusChip(label: piece.estado, definitivo: piece.definitivo, compact: true),
                    if (piece.enVivo) const _EnVivoBadge(),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(LucideIcons.userRound, size: 15, color: dim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(piece.destinatario.isEmpty ? 'Sin destinatario' : piece.destinatario,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  if (piece.localidad.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      Icon(LucideIcons.mapPin, size: 15, color: dim),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(piece.localidad,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim)),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Row(children: [
                    Icon(LucideIcons.boxes, size: 14, color: dim),
                    const SizedBox(width: 5),
                    Text('${piece.cantidad} ${piece.cantidad == 1 ? 'bulto' : 'bultos'}',
                        style: TextStyle(fontSize: 12.5, color: dim)),
                    const SizedBox(width: 14),
                    Icon(LucideIcons.clock, size: 14, color: dim),
                    const SizedBox(width: 5),
                    Text(piece.fecha == null ? '' : fmtDate(piece.fecha!),
                        style: TextStyle(fontSize: 12.5, color: dim)),
                    const Spacer(),
                    Icon(LucideIcons.chevronRight, size: 18, color: cs.onSurface.withValues(alpha: 0.4)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GridHeader extends StatelessWidget {
  const _GridHeader();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.primary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Row(children: [
        SizedBox(width: 108, child: Text('Nº', style: s)),
        Expanded(child: Text('DESTINATARIO', style: s)),
        SizedBox(width: 56, child: Text('FECHA', style: s)),
        SizedBox(width: 96, child: Text('ESTADO', style: s)),
      ]),
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({required this.piece, required this.odd, required this.onTap});
  final Piece piece;
  final bool odd;
  final void Function(Piece) onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = StatusColors.of(context, definitivo: piece.definitivo);
    return InkWell(
      onTap: () => onTap(piece),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: odd ? cs.surface : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: Row(children: [
          SizedBox(
            width: 108,
            child: Text(piece.tracking,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(piece.destinatario,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (piece.localidad.isNotEmpty)
                Text(piece.localidad,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: 0.55))),
            ]),
          ),
          SizedBox(
            width: 56,
            child: Text(piece.fecha == null ? '' : fmtDate(piece.fecha!),
                style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7))),
          ),
          SizedBox(
            width: 96,
            child: Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(piece.estado,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: cs.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65))),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Container(
      height: 132,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(20)),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.5, end: 1, duration: 900.ms);
  }
}

/// Insignia de las piezas que se pueden seguir en tiempo real.
class _EnVivoBadge extends StatelessWidget {
  const _EnVivoBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: StatusColors.gestionDark, shape: BoxShape.circle),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.3, end: 1, duration: 800.ms),
          const SizedBox(width: 5),
          const Text('EN VIVO',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ]),
      );
}
