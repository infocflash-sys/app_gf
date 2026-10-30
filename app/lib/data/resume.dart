import 'package:shared_preferences/shared_preferences.dart';

/// Punto al que volver si Android cierra la app mientras estaba en segundo plano
/// (por poca memoria): la pieza que se estaba viendo y si tenía el mapa abierto.
class ResumePoint {
  const ResumePoint({required this.pieceId, required this.mapOpen, required this.at});
  final int pieceId;
  final bool mapOpen;
  final DateTime at;
}

class ResumeStore {
  static const _kId = 'resume_piece';
  static const _kMap = 'resume_map';
  static const _kAt = 'resume_at';

  /// Pasado este tiempo ya no se retoma: se abre la lista como siempre.
  static const maxAge = Duration(minutes: 30);

  static Future<void> save(int pieceId, {required bool mapOpen}) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kId, pieceId);
      await p.setBool(_kMap, mapOpen);
      await p.setInt(_kAt, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kId);
      await p.remove(_kMap);
      await p.remove(_kAt);
    } catch (_) {}
  }

  static Future<ResumePoint?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final id = p.getInt(_kId);
      final at = p.getInt(_kAt);
      if (id == null || at == null) return null;
      final when = DateTime.fromMillisecondsSinceEpoch(at);
      if (DateTime.now().difference(when) > maxAge) return null;
      return ResumePoint(pieceId: id, mapOpen: p.getBool(_kMap) ?? false, at: when);
    } catch (_) {
      return null;
    }
  }
}
