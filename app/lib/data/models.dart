import 'package:latlong2/latlong.dart';

class Profile {
  const Profile({required this.cliente, required this.clientes});

  /// Nombre del cliente (no del usuario): es el que se usa en la bienvenida.
  final String cliente;
  final List<String> clientes;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        cliente: (j['cliente'] as String).trim(),
        clientes: [
          for (final c in (j['clientes'] as List? ?? const []))
            (c['nombre'] as String).trim(),
        ],
      );

  Map<String, dynamic> toJson() => {
        'cliente': cliente,
        'clientes': [for (final c in clientes) {'nombre': c}],
      };
}

/// Pieza tal como se muestra en la lista.
class Piece {
  const Piece({
    required this.id,
    required this.tracking,
    required this.destinatario,
    required this.localidad,
    required this.cantidad,
    required this.estado,
    required this.definitivo,
    required this.fecha,
    this.trackingExterno,
    this.remito,
    this.actualizado,
    this.enVivo = false,
  });

  final int id;
  final String tracking;
  final String? trackingExterno;
  final String? remito;
  final String destinatario;
  final String localidad;
  final int cantidad;
  final String estado;

  /// true = estado definitivo (tarjeta azul). false = aún en gestión (verde).
  final bool definitivo;
  final DateTime? fecha;
  final DateTime? actualizado;

  /// true si la pieza está hoy en un recorrido abierto: se puede seguir en tiempo real.
  final bool enVivo;

  factory Piece.fromJson(Map<String, dynamic> j) => Piece(
        id: j['id'] as int,
        tracking: '${j['tracking'] ?? j['id']}',
        trackingExterno: j['trackingExterno'] as String?,
        remito: j['remito'] as String?,
        destinatario: ((j['destinatario'] as String?) ?? '').trim(),
        localidad: ((j['localidad'] as String?) ?? '').trim(),
        cantidad: (j['cantidad'] as num?)?.toInt() ?? 1,
        estado: ((j['estado'] as String?) ?? 'Sin estado').trim(),
        definitivo: j['definitivo'] == true,
        fecha: _date(j['fecha']),
        actualizado: _date(j['actualizado']),
        enVivo: j['enVivo'] == true,
      );
}

class Resumen {
  const Resumen({
    required this.total,
    required this.enGestion,
    required this.finalizadas,
    required this.enRecorrido,
    required this.dias,
  });
  final int total;
  final int enGestion;
  final int finalizadas;

  /// Piezas "En distribución" con recorrido abierto ahora mismo (listas para el mapa en vivo).
  final int enRecorrido;
  final int dias;

  factory Resumen.fromJson(Map<String, dynamic> j) => Resumen(
        total: j['total'] as int,
        enGestion: j['enGestion'] as int,
        finalizadas: j['finalizadas'] as int,
        enRecorrido: (j['enRecorrido'] as num?)?.toInt() ?? 0,
        dias: j['dias'] as int,
      );
}

class PiecePage {
  const PiecePage({required this.items, required this.hasMore, this.resumen});
  final List<Piece> items;
  final bool hasMore;
  final Resumen? resumen;

  factory PiecePage.fromJson(Map<String, dynamic> j) => PiecePage(
        items: [for (final p in (j['items'] as List)) Piece.fromJson(p as Map<String, dynamic>)],
        hasMore: j['hasMore'] == true,
        resumen: j['resumen'] == null ? null : Resumen.fromJson(j['resumen'] as Map<String, dynamic>),
      );
}

class TrackEvent {
  const TrackEvent({
    required this.id,
    required this.estado,
    required this.definitivo,
    required this.fecha,
    required this.foto,
    required this.firma,
  });
  final int id;
  final String estado;
  final bool definitivo;
  final DateTime? fecha;
  final bool foto;
  final bool firma;

  factory TrackEvent.fromJson(Map<String, dynamic> j) => TrackEvent(
        id: j['id'] as int,
        estado: ((j['estado'] as String?) ?? 'Sin estado').trim(),
        definitivo: j['definitivo'] == true,
        fecha: _date(j['fecha']),
        foto: j['foto'] == true,
        firma: j['firma'] == true,
      );
}

class PieceDetail {
  const PieceDetail({
    required this.piece,
    required this.domicilio,
    required this.bultos,
    required this.pesoKg,
    required this.pdf,
    required this.eventos,
  });
  final Piece piece;
  final String domicilio;
  final int bultos;
  final double? pesoKg;
  final bool pdf;
  final List<TrackEvent> eventos;

  factory PieceDetail.fromJson(Map<String, dynamic> j) => PieceDetail(
        piece: Piece.fromJson(j),
        domicilio: ((j['domicilio'] as String?) ?? '').trim(),
        bultos: (j['bultos'] as num?)?.toInt() ?? 1,
        pesoKg: (j['pesoKg'] as num?)?.toDouble(),
        pdf: j['pdf'] == true,
        eventos: [for (final e in (j['eventos'] as List)) TrackEvent.fromJson(e as Map<String, dynamic>)],
      );
}

/// Última posición conocida del vehículo que lleva la pieza.
class VehiclePosition {
  const VehiclePosition({required this.point, required this.fecha, required this.sinSenal});
  final LatLng point;
  final DateTime? fecha;

  /// Más de 15 minutos sin puntos GPS.
  final bool sinSenal;
}

/// Una lectura GPS reciente del vehículo, para la transición animada en cadena.
class TrailPoint {
  const TrailPoint({required this.point, required this.fecha});
  final LatLng point;
  final DateTime? fecha;
}

/// Seguimiento en tiempo real de una pieza (recorrido abierto).
class LiveTracking {
  const LiveTracking({
    required this.activo,
    this.recorrido,
    this.tipo,
    this.destino,
    this.destinoNombre,
    this.vehiculo,
    this.puntosRecientes = const [],
    this.inicioRecorrido,
    this.proximaEntrega = false,
  });
  final bool activo;
  final int? recorrido;

  /// 'ENTREGA', 'RETIRO' o 'TRASLADO' (traslado entre sucursales, vía despacho).
  final String? tipo;
  final LatLng? destino;

  /// Nombre de la sucursal destino, solo cuando tipo == 'TRASLADO'.
  final String? destinoNombre;
  final VehiclePosition? vehiculo;

  /// Últimas lecturas GPS del cartero (de más vieja a más nueva, hasta 3), tal cual se subieron
  /// en el último lote: la app las anima en cadena en vez de saltar directo a la más nueva.
  final List<TrailPoint> puntosRecientes;

  /// Primer punto GPS del cartero hoy (hora en que salió "a la calle" con este recorrido).
  final DateTime? inicioRecorrido;

  /// true si, de todas las piezas del recorrido aún no entregadas, esta es la de orden más bajo.
  final bool proximaEntrega;

  bool get esRetiro => tipo == 'RETIRO';
  bool get esTraslado => tipo == 'TRASLADO';

  factory LiveTracking.fromJson(Map<String, dynamic> j) {
    LatLng? pt(Object? o) => o is Map ? LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble()) : null;
    final v = j['vehiculo'];
    return LiveTracking(
      activo: j['activo'] == true,
      recorrido: j['recorrido'] as int?,
      tipo: j['tipo'] as String?,
      destino: pt(j['destino']),
      destinoNombre: (j['destinoNombre'] as String?)?.trim(),
      vehiculo: v is Map
          ? VehiclePosition(
              point: pt(v)!,
              fecha: _date(v['fecha']),
              sinSenal: v['sinSenal'] == true,
            )
          : null,
      puntosRecientes: [
        for (final p in (j['puntosRecientes'] as List? ?? []))
          if (p is Map && pt(p) != null) TrailPoint(point: pt(p)!, fecha: _date(p['fecha'])),
      ],
      inicioRecorrido: _date(j['inicioRecorrido']),
      proximaEntrega: j['proximaEntrega'] == true,
    );
  }
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
