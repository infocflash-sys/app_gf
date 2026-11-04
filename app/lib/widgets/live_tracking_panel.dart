import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/models.dart';
import '../data/portal_api.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';

/// Una lectura GPS pendiente de animar (en espera dentro de la cadena A→B→C).
class _Waypoint {
  const _Waypoint(this.point, this.fecha);
  final LatLng point;
  final DateTime? fecha;
}

/// "Sigue en tiempo real": mapa con el móvil que lleva la pieza y el punto de entrega,
/// al estilo de las apps de delivery. Se actualiza solo mientras está abierto.
class LiveTrackingPanel extends StatefulWidget {
  const LiveTrackingPanel({
    super.key,
    required this.fetch,
    this.interval = const Duration(seconds: 15),
    this.showMap = true,
    this.height = 400,
    this.fullScreen = false,
    this.onExpand,
    this.onUpdate,
    this.pieceId,
    this.tracking,
    this.destinatario,
    this.domicilio,
  });

  final Future<LiveTracking> Function() fetch;
  final Duration interval;

  /// false solo en tests (evita descargar mosaicos del mapa).
  final bool showMap;

  /// Alto del panel cuando va dentro del detalle. En pantalla completa ocupa todo el espacio.
  final double height;

  /// true cuando el mapa se muestra a pantalla completa (sin esquinas redondeadas ni botón de ampliar).
  final bool fullScreen;

  /// Si se informa, aparece el botón para abrir el mapa a pantalla completa.
  final VoidCallback? onExpand;

  /// Se llama con cada actualización recibida (por ejemplo, para mostrar "Inicio de recorrido" afuera del mapa).
  final ValueChanged<LiveTracking>? onUpdate;

  // Datos fijos de la pieza (no cambian entre sondeos), para los popups al tocar los íconos.
  final int? pieceId;
  final String? tracking;
  final String? destinatario;
  final String? domicilio;

  @override
  State<LiveTrackingPanel> createState() => _LiveTrackingPanelState();
}

class _LiveTrackingPanelState extends State<LiveTrackingPanel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _map = MapController();
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  Timer? _timer;
  LiveTracking? _data;
  String? _error;
  LatLng? _from; // posición anterior del móvil (para animar el desplazamiento)
  LatLng? _to; // posición actual
  DateTime? _toFecha; // fecha real de la lectura en la que está parado/llegando _to
  final List<_Waypoint> _queue = []; // próximas lecturas del último lote, a animar en cadena
  bool _follow = true; // mientras no se mueva el mapa a mano, se mantiene encuadrado
  int _gen = 0;

  static const _geo = Distance();
  final List<LatLng> _trail = []; // lecturas recibidas desde que se abrió el mapa: dibujan la estela
  double _heading = 0; // hacia dónde avanza el móvil (radianes, 0 = norte)

  LatLng? get _vehicle {
    final to = _to;
    if (to == null) return null;
    final from = _from ?? to;
    if (from == to) return to;
    final t = _anim.value;

    // Curva suave (Catmull-Rom) en vez de una recta dura entre dos lecturas: usa también el punto
    // anterior a "from" y el siguiente después de "to" (ya en cola) como apoyo, para que la cadena
    // A→B→C se sienta continua en las esquinas en vez de quebrar de golpe en cada GPS.
    final n = _trail.length;
    final p0 = n >= 3 ? _trail[n - 3] : from;
    final p3 = _queue.isNotEmpty
        ? _queue.first.point
        : LatLng(to.latitude * 2 - from.latitude, to.longitude * 2 - from.longitude);
    return _catmullRom(p0, from, to, p3, t);
  }

  /// Interpolación Catmull-Rom uniforme, componente a componente (lat/lng por separado alcanza
  /// para distancias cortas entre lecturas GPS consecutivas).
  static LatLng _catmullRom(LatLng p0, LatLng p1, LatLng p2, LatLng p3, double t) {
    double seg(double a0, double a1, double a2, double a3) {
      final t2 = t * t;
      final t3 = t2 * t;
      return 0.5 *
          ((2 * a1) +
              (-a0 + a2) * t +
              (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2 +
              (-a0 + 3 * a1 - 3 * a2 + a3) * t3);
    }

    return LatLng(
      seg(p0.latitude, p1.latitude, p2.latitude, p3.latitude),
      seg(p0.longitude, p1.longitude, p2.longitude, p3.longitude),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anim.addStatusListener(_onAnimStatus);
    _poll();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _anim.removeStatusListener(_onAnimStatus);
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  /// Al terminar cada tramo, sigue con el próximo de la cola (si hay) para formar la cadena.
  void _onAnimStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _playNext();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _poll();
      if (_data?.activo != false) _startTimer();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel(); // sin pantalla no se consulta
    }
  }

  Future<void> _poll() async {
    final gen = ++_gen;
    try {
      final d = await widget.fetch();
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = null;
        final puntos = d.puntosRecientes;
        if (puntos.isEmpty) {
          if (_to == null) {
            _from = null;
            _to = null;
            _toFecha = null;
            _queue.clear();
            _trail.clear();
          }
          // si ya había una posición, se deja la última conocida (puede estar "sin señal")
        } else if (_to == null) {
          // primera vez: en vez de ubicar directo en la lectura más nueva y quedar estático hasta
          // el próximo sondeo (~15 s de "mapa congelado" que se siente poco vivo), arranca desde
          // unas lecturas atrás y encola el resto para animar la cadena ya mismo: se ve movimiento
          // apenas se abre el mapa, en vez de esperar.
          const catchUp = 6;
          final window = puntos.length > catchUp ? puntos.sublist(puntos.length - catchUp) : puntos;
          final start = window.first;
          _from = start.point;
          _to = start.point;
          _toFecha = start.fecha;
          _anim.value = 1;
          _trail
            ..clear()
            ..add(start.point);
          _queue.clear();
          for (final p in window.skip(1)) {
            _queue.add(_Waypoint(p.point, p.fecha));
          }
        } else {
          // encola las lecturas realmente nuevas (posteriores a la última ya animada o en cola),
          // en el orden real en que se capturaron: la cadena A→B→C "rellena" el minuto entre una
          // subida del cartero y la siguiente en vez de saltar y quedar congelada hasta esa subida.
          final cursor = _queue.isNotEmpty ? _queue.last.fecha : _toFecha;
          for (final p in puntos) {
            if (cursor != null && p.fecha != null && !p.fecha!.isAfter(cursor)) continue;
            _queue.add(_Waypoint(p.point, p.fecha));
          }
        }
        _data = d;
      });
      widget.onUpdate?.call(d);
      if (!d.activo) _timer?.cancel(); // el recorrido terminó: se deja de consultar
      if (_anim.isCompleted) _playNext(); // nada animándose: arranca la cola nueva ya mismo
      if (_follow) _fitAll();
    } on ApiException catch (e) {
      if (mounted && gen == _gen) setState(() => _error = e.message);
    }
  }

  /// Anima el siguiente tramo de la cadena (si hay alguno en cola), con la cadencia real
  /// entre esa lectura y la anterior. Se dispara al llegar datos nuevos y al terminar cada tramo.
  void _playNext() {
    if (_queue.isEmpty || !mounted) return;
    final next = _queue.removeAt(0);
    setState(() {
      final prevTo = _to;
      final prevFecha = _toFecha;
      final metros = prevTo != null ? _geo.as(LengthUnit.Meter, prevTo, next.point) : 0.0;
      if (metros > 5 && prevTo != null) _heading = _geo.bearing(prevTo, next.point) * math.pi / 180;
      _from = _vehicle; // arranca desde donde se está dibujando ahora mismo
      _to = next.point;
      _toFecha = next.fecha;
      _trail.add(next.point);
      if (_trail.length > 40) _trail.removeAt(0);
      _anim.duration = _driftDuration(metros, prevFecha, next.fecha);
      _anim.forward(from: 0);
    });
  }

  /// Cuánto dura el desplazamiento animado entre una lectura GPS y la siguiente.
  /// Se basa en el tiempo real transcurrido entre ambas (más inmersivo que asumir
  /// siempre el intervalo fijo de sondeo), con un piso y un techo para que nunca
  /// se sienta brusco ni eternamente lento. Un salto enorme (posible corte de GPS
  /// o reinicio de posición) se traslada rápido en vez de "patinar" por el mapa.
  /// Velocidad llevada a un 33% de la original (factor ×3) para una transición
  /// más inmersiva, tipo Uber/PedidosYa, en vez de un desplazamiento brusco.
  static const _driftSlowdown = 3;

  static Duration _driftDuration(double metros, DateTime? antes, DateTime? ahora) {
    if (metros > 1500) return const Duration(milliseconds: 500 * _driftSlowdown);
    if (antes != null && ahora != null) {
      final gapMs = ahora.difference(antes).inMilliseconds;
      if (gapMs > 0) {
        return Duration(milliseconds: (gapMs * _driftSlowdown).clamp(800 * _driftSlowdown, 4000 * _driftSlowdown));
      }
    }
    return const Duration(milliseconds: 2000 * _driftSlowdown); // sin fecha previa: valor razonable por defecto
  }

  // ---------------- cámara ----------------

  void _afterFrame(void Function() f) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !widget.showMap) return;
        try {
          f();
        } catch (_) {} // el mapa todavía no está listo
      });

  /// Encuadra el móvil y el punto de entrega.
  void _fitAll() {
    final pts = [?_to, ?_data?.destino];
    if (pts.isEmpty) return;
    _afterFrame(() {
      if (pts.length == 1) {
        _map.move(pts.first, 15.5);
      } else {
        _map.fitCamera(CameraFit.coordinates(
          coordinates: pts,
          padding: const EdgeInsets.fromLTRB(70, 80, 70, 170),
          maxZoom: 16.5,
        ));
      }
    });
  }

  /// Centra el mapa en el móvil.
  void _centerOnVehicle() {
    final v = _to;
    if (v == null) return;
    setState(() => _follow = false);
    _afterFrame(() => _map.move(v, 16.5));
  }

  void _zoom(double delta) {
    setState(() => _follow = false);
    _afterFrame(() {
      final cam = _map.camera;
      _map.move(cam.center, (cam.zoom + delta).clamp(3.0, 19.0));
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final full = widget.fullScreen;
    final pad = full ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    return ClipRRect(
      borderRadius: BorderRadius.circular(full ? 0 : 24),
      child: SizedBox(
        height: full ? null : widget.height,
        child: Stack(children: [
          Positioned.fill(
            child: widget.showMap ? _mapView(context, d) : const ColoredBox(color: Brand.navyDeep),
          ),
          // a pantalla completa el botón "volver" ocupa la esquina, por eso el aviso va corrido
          Positioned(top: 12 + pad.top + (full ? 4 : 0), left: full ? 66 : 12, child: const _LiveBadge()),
          if (!full && widget.onExpand != null)
            Positioned(
              top: 8,
              right: 12,
              child: _MapCardButton(
                icon: LucideIcons.maximize2,
                tooltip: 'Ver en pantalla completa',
                onTap: widget.onExpand!,
              ),
            ),
          if (widget.showMap && d?.activo == true)
            Positioned(
              right: 12,
              top: full ? 12 + pad.top : 56,
              child: _Controls(
                onZoomIn: () => _zoom(1),
                onZoomOut: () => _zoom(-1),
                onCenter: _to == null ? null : _centerOnVehicle,
                onFit: () {
                  setState(() => _follow = true);
                  _fitAll();
                },
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + pad.bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (d?.activo == true && d?.proximaEntrega == true) ...[
                  const _NextDeliveryBanner(),
                  const SizedBox(height: 8),
                ],
                _statusCard(context, d),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // OpenStreetMap estándar: gratis, sin cuenta ni API key (a diferencia de CARTO, que empezó a
  // exigirla incluso en su tier gratuito). Para el modo oscuro no hay un estilo oficial gratis,
  // así que se simula invirtiendo los mismos tiles y corrigiendo el matiz (el mismo truco que
  // "filter: invert(1) hue-rotate(180deg))" en CSS).
  static const _invertMatrix = <double>[
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];

  static const _hueRotate180Matrix = <double>[
    -0.574, 1.430, 0.144, 0, 0,
    0.426, 0.430, 0.144, 0, 0,
    0.426, 1.430, -0.856, 0, 0,
    0, 0, 0, 1, 0,
  ];

  Widget _osmTiles(bool dark) {
    final tiles = TileLayer(
      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: const ['a', 'b', 'c'],
      userAgentPackageName: 'com.grupoflash.portal',
      maxZoom: 19,
    );
    if (!dark) return tiles;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(_hueRotate180Matrix),
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(_invertMatrix),
        child: tiles,
      ),
    );
  }

  Widget _mapView(BuildContext context, LiveTracking? d) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final destino = d?.destino;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _to ?? destino ?? const LatLng(-34.6037, -58.3816),
        initialZoom: 14.5,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom,
        ),
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _follow) setState(() => _follow = false);
        },
      ),
      children: [
        _osmTiles(dark),
        if (destino != null)
          MarkerLayer(markers: [
            Marker(
              point: destino,
              width: 64,
              height: 72,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _showDestinoInfo(context, d),
                child: _DestinationMarker(retiro: d?.esRetiro ?? false, traslado: d?.esTraslado ?? false),
              ),
            ),
          ]),
        AnimatedBuilder(
          animation: _anim,
          builder: (_, _) {
            final v = _vehicle;
            return MarkerLayer(markers: [
              if (v != null)
                Marker(
                  point: v,
                  width: 76,
                  height: 76,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _showVehiculoInfo(context, d),
                    child: _VehicleMarker(
                      stale: d?.vehiculo?.sinSenal ?? false,
                      heading: _trail.length > 1 ? _heading : null,
                    ),
                  ),
                ),
            ]);
          },
        ),
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
        ),
      ],
    );
  }

  void _showDestinoInfo(BuildContext context, LiveTracking? d) {
    final traslado = d?.esTraslado ?? false;
    final retiro = d?.esRetiro ?? false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InfoSheet(
        title: traslado ? 'Sucursal de destino' : (retiro ? 'Punto de retiro' : 'Punto de entrega'),
        icon: traslado ? LucideIcons.warehouse : (retiro ? LucideIcons.packageOpen : LucideIcons.house),
        rows: traslado
            ? [('Sucursal', d?.destinoNombre?.isNotEmpty == true ? d!.destinoNombre! : 'Sin datos')]
            : [
                ('Destinatario', widget.destinatario?.isNotEmpty == true ? widget.destinatario! : 'Sin datos'),
                ('Domicilio', widget.domicilio?.isNotEmpty == true ? widget.domicilio! : 'Sin datos'),
              ],
      ),
    );
  }

  void _showVehiculoInfo(BuildContext context, LiveTracking? d) {
    final fecha = d?.vehiculo?.fecha;
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _InfoSheet(
        title: 'Seguimiento',
        icon: LucideIcons.truck,
        rows: [
          if (widget.pieceId != null) ('Nº de pieza', '#${widget.pieceId}'),
          if (widget.tracking?.isNotEmpty == true) ('Nº de seguimiento', widget.tracking!),
          ('Última posición', fecha == null ? 'Sin datos' : fmtDateTime(fecha)),
        ],
      ),
    );
  }

  Widget _statusCard(BuildContext context, LiveTracking? d) {
    final cs = Theme.of(context).colorScheme;
    String title;
    String subtitle;
    IconData icon = LucideIcons.truck;
    Color color = StatusColors.of(context, definitivo: false);
    Widget? ago;

    if (d == null) {
      title = _error == null ? 'Buscando el vehículo…' : 'No pudimos cargar la ubicación';
      subtitle = _error ?? 'Un momento, por favor.';
      color = cs.primary;
      if (_error != null) icon = LucideIcons.wifiOff;
    } else if (!d.activo) {
      title = 'El seguimiento en vivo ya no está disponible';
      subtitle = 'El recorrido finalizó o la pieza cambió de estado.';
      icon = LucideIcons.circleCheck;
      color = cs.primary;
    } else if (d.vehiculo == null) {
      title = 'Sin señal del vehículo por ahora';
      subtitle = 'Apenas recibamos su ubicación la vas a ver en el mapa.';
      icon = LucideIcons.satelliteDish;
      color = cs.onSurface.withValues(alpha: 0.6);
    } else if (d.vehiculo!.sinSenal) {
      title = 'Sin señal reciente';
      subtitle = 'Última ubicación conocida';
      icon = LucideIcons.satelliteDish;
      color = StatusColors.novedad;
      ago = _AgoText(d.vehiculo!.fecha);
    } else if (d.esTraslado) {
      title = d.destinoNombre?.isNotEmpty == true
          ? 'Tu pieza va camino a ${d.destinoNombre}'
          : 'Tu pieza va camino a otra sucursal';
      subtitle = 'Se actualiza sola cada pocos segundos';
      ago = _AgoText(d.vehiculo!.fecha);
    } else {
      title = d.esRetiro ? 'Vamos en camino a retirar tu pieza' : 'Tu pieza está en camino';
      subtitle = 'Se actualiza sola cada pocos segundos';
      ago = _AgoText(d.vehiculo!.fecha);
    }

    return Material(
      color: cs.surface,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.65), fontSize: 12.5)),
              if (ago != null) ...[const SizedBox(height: 2), ago],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Aviso de que, entre todas las piezas aún pendientes del recorrido, esta es la próxima a entregar.
class _NextDeliveryBanner extends StatelessWidget {
  const _NextDeliveryBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Brand.navy,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: const Icon(LucideIcons.packageCheck, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Tu pieza es la próxima en ser entregada',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Última señal hace X", que se refresca sola sin reconstruir el mapa.
class _AgoText extends StatefulWidget {
  const _AgoText(this.fecha);
  final DateTime? fecha;

  @override
  State<_AgoText> createState() => _AgoTextState();
}

class _AgoTextState extends State<_AgoText> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _text() {
    final f = widget.fecha;
    if (f == null) return '';
    final s = DateTime.now().difference(f).inSeconds.clamp(0, 1 << 30);
    if (s < 60) return 'Última señal hace $s s';
    if (s < 3600) return 'Última señal hace ${s ~/ 60} min';
    return 'Última señal hace ${s ~/ 3600} h';
  }

  @override
  Widget build(BuildContext context) => Text(
        _text(),
        style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
      );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Brand.ink.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: StatusColors.gestionDark, shape: BoxShape.circle),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.3, end: 1, duration: 800.ms),
          const SizedBox(width: 6),
          const Text('EN VIVO',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
      );
}

/// Botón suelto sobre el mapa (por ejemplo, "pantalla completa").
class _MapCardButton extends StatelessWidget {
  const _MapCardButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 4,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(16),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 21),
        color: cs.onSurface,
        style: IconButton.styleFrom(minimumSize: const Size(42, 42)),
      ),
    );
  }
}

/// Botones del mapa: acercar, alejar, centrar en el móvil y ver todo.
class _Controls extends StatelessWidget {
  const _Controls({required this.onZoomIn, required this.onZoomOut, required this.onCenter, required this.onFit});
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onCenter;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 21),
          color: cs.onSurface,
          style: IconButton.styleFrom(minimumSize: const Size(42, 42)),
        );
    return Material(
      color: cs.surface,
      elevation: 4,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        btn(LucideIcons.plus, 'Acercar', onZoomIn),
        Divider(height: 1, indent: 8, endIndent: 8, color: cs.outlineVariant),
        btn(LucideIcons.minus, 'Alejar', onZoomOut),
        Divider(height: 1, indent: 8, endIndent: 8, color: cs.outlineVariant),
        btn(LucideIcons.locateFixed, 'Centrar en el vehículo', onCenter),
        Divider(height: 1, indent: 8, endIndent: 8, color: cs.outlineVariant),
        btn(LucideIcons.maximize, 'Ver vehículo y entrega', onFit),
      ]),
    );
  }
}

/// Móvil con el paquete: camión sobre un círculo marino, con la insignia de la caja que transporta.
class _VehicleMarker extends StatelessWidget {
  const _VehicleMarker({required this.stale, this.heading});
  final bool stale;

  /// Rumbo en radianes (0 = norte). null mientras todavía no hay movimiento que mostrar.
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final base = stale ? const Color(0xFF6B7280) : Brand.navy;
    return Stack(alignment: Alignment.center, children: [
      if (!stale)
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.accent.withValues(alpha: 0.28)),
        )
            .animate(onPlay: (c) => c.repeat())
            .scale(begin: const Offset(0.55, 0.55), end: const Offset(1.1, 1.1), duration: 1500.ms)
            .fadeOut(duration: 1500.ms),
      Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: base,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: const Icon(LucideIcons.truck, size: 22, color: Colors.white),
      ),
      // flecha de dirección: gira hacia donde avanza el camión
      if (heading != null && !stale)
        SizedBox(
          width: 76,
          height: 76,
          child: Transform.rotate(
            angle: heading!,
            child: const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.navigation, size: 20, color: Brand.accent, shadows: [
                  Shadow(color: Colors.white, blurRadius: 4),
                ]),
              ),
            ),
          ),
        ),
      // la caja que lleva
      Positioned(
        right: 8,
        bottom: 8,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: stale ? const Color(0xFFBFC4CC) : Brand.flash,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Icon(LucideIcons.package, size: 13, color: Brand.navyDeep),
        ),
      ),
    ]);
  }
}

/// Punto de entrega: pin con una casa, una caja (retiro) o un depósito (traslado entre sucursales).
class _DestinationMarker extends StatelessWidget {
  const _DestinationMarker({required this.retiro, this.traslado = false});
  final bool retiro;
  final bool traslado;

  @override
  Widget build(BuildContext context) {
    final icon = traslado ? LucideIcons.warehouse : (retiro ? LucideIcons.packageOpen : LucideIcons.house);
    return Stack(alignment: Alignment.topCenter, children: [
      const Icon(Icons.location_on, size: 66, color: StatusColors.novedad, shadows: [
        Shadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 2)),
      ]),
      Positioned(
        top: 12,
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
          child: Icon(icon, size: 17, color: StatusColors.novedad),
        ),
      ),
    ]);
  }
}

/// Bottom sheet con los datos al tocar un ícono del mapa (destino o vehículo).
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.icon, required this.rows});
  final String title;
  final IconData icon;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Row(children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 16),
          for (final (label, value) in rows) ...[
            Text(label, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55), fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 14),
          ],
        ]),
      ),
    );
  }
}
