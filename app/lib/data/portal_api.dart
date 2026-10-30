import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'models.dart';
import 'resume.dart';

class ApiException implements Exception {
  ApiException(this.code, this.message, [this.status = 0]);
  final String code;
  final String message;
  final int status;

  bool get isNetwork => code == 'NETWORK';
  @override
  String toString() => message;
}

/// Códigos con los que la API indica que la cuenta ya no puede usar la app.
const _endSessionCodes = {
  'REVOKED', 'ACCOUNT_DISABLED', 'CLIENT_DISABLED', 'NOT_CLIENT', 'BAD_TOKEN',
};

/// Cliente de la API del portal: sesión permanente cifrada en el equipo,
/// renovación automática del acceso y cierre inmediato si la cuenta se desactiva.
class PortalApi {
  PortalApi({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _store = const FlutterSecureStorage();

  String? _access;
  String? _refresh;
  Future<void>? _refreshing;

  Profile? profile;

  /// Se completa con un mensaje cuando la sesión se cierra por decisión del servidor.
  final ValueNotifier<String?> sessionEnded = ValueNotifier(null);

  static const _kRefresh = 'refresh_token';
  static const _kProfile = 'profile';
  static const _kGreeted = 'greeted_on';

  // ---------------- sesión ----------------

  Future<Profile> login(String usuario, String clave) async {
    final j = await _request('POST', '/auth/login',
        body: {'usuario': usuario.trim(), 'clave': clave}, auth: false) as Map<String, dynamic>;
    await _adopt(j);
    sessionEnded.value = null;
    return profile!;
  }

  /// Al abrir la app. Devuelve el perfil si hay sesión guardada y sigue válida,
  /// o null si no hay sesión. Si la cuenta fue desactivada, lanza ApiException.
  Future<Profile?> restore() async {
    _refresh = await _read(_kRefresh);
    if (_refresh == null) return null;
    final cached = await _read(_kProfile);
    try {
      await _refreshTokens();
      return profile;
    } on ApiException catch (e) {
      if (e.isNetwork && cached != null) {
        // sin conexión: se entra con el último perfil y se revalida al primer pedido
        profile = Profile.fromJson(jsonDecode(cached) as Map<String, dynamic>);
        return profile;
      }
      rethrow;
    }
  }

  Future<void> logout() async {
    _access = null;
    _refresh = null;
    profile = null;
    _imageCache.clear();
    await _delete(_kRefresh);
    await _delete(_kProfile);
    await ResumeStore.clear();
  }

  Future<void> _adopt(Map<String, dynamic> j) async {
    _access = j['accessToken'] as String;
    _refresh = j['refreshToken'] as String;
    profile = Profile.fromJson(j);
    await _write(_kRefresh, _refresh!);
    await _write(_kProfile, jsonEncode(profile!.toJson()));
  }

  Future<void> _refreshTokens() {
    return _refreshing ??= () async {
      try {
        final j = await _request('POST', '/auth/refresh',
            body: {'refreshToken': _refresh}, auth: false) as Map<String, dynamic>;
        await _adopt(j);
      } on ApiException catch (e) {
        if (_endSessionCodes.contains(e.code) || e.status == 401 || e.status == 403) {
          await _endSession(e.message);
        }
        rethrow;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<void> _endSession(String message) async {
    await logout();
    sessionEnded.value = message;
  }

  // ---------------- saludo diario ----------------

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  Future<bool> shouldGreetToday() async => (await _read(_kGreeted)) != _today();
  Future<void> markGreeted() => _write(_kGreeted, _today());

  // ---------------- datos ----------------

  Future<PiecePage> pieces({int page = 1, String q = '', String? grupo, int dias = 30}) async {
    final j = await _request('GET', '/piezas', query: {
      'page': '$page',
      'size': '30',
      'dias': '$dias',
      if (q.trim().isNotEmpty) 'q': q.trim(),
      'grupo': ?grupo,
    });
    return PiecePage.fromJson(j as Map<String, dynamic>);
  }

  Future<PieceDetail> detail(int id) async =>
      PieceDetail.fromJson(await _request('GET', '/piezas/$id') as Map<String, dynamic>);

  /// Seguimiento en tiempo real (vehículo y destino). Solo disponible si la pieza está en un recorrido abierto.
  Future<LiveTracking> tracking(int id) async =>
      LiveTracking.fromJson(await _request('GET', '/piezas/$id/seguimiento') as Map<String, dynamic>);

  final Map<String, Uint8List> _imageCache = {};

  /// Foto o firma de un evento. kind: 'foto' | 'firma'.
  Future<Uint8List> eventImage(int pieceId, int eventId, String kind, {bool full = false}) async {
    final key = '$pieceId/$eventId/$kind/${full ? 'f' : 't'}';
    final hit = _imageCache[key];
    if (hit != null) return hit;
    final bytes = await _bytes('/piezas/$pieceId/eventos/$eventId/$kind', {'size': full ? 'full' : 'thumb'});
    if (_imageCache.length > 80) _imageCache.remove(_imageCache.keys.first);
    return _imageCache[key] = bytes;
  }

  /// Descarga el PDF de la pieza a un archivo temporal y devuelve su ruta.
  Future<File> pdfFile(int pieceId) async {
    final bytes = await _bytes('/piezas/$pieceId/pdf');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/pieza_$pieceId.pdf');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  // ---------------- HTTP ----------------

  Future<http.Response> _send(String method, String path,
      {Map<String, String>? query, Object? body, bool auth = true, bool retry = true}) async {
    final uri = Uri.parse('${AppConfig.apiUrl}$path').replace(queryParameters: query);
    final headers = {
      'content-type': 'application/json',
      if (auth && _access != null) 'authorization': 'Bearer $_access',
    };
    http.Response r;
    try {
      final f = method == 'GET'
          ? _http.get(uri, headers: headers)
          : _http.post(uri, headers: headers, body: jsonEncode(body));
      r = await f.timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw ApiException('NETWORK', 'La conexión tardó demasiado. Reintentá en un momento.');
    } on SocketException {
      throw ApiException('NETWORK', 'Sin conexión. Revisá tu internet e intentá nuevamente.');
    } on http.ClientException {
      throw ApiException('NETWORK', 'Sin conexión. Revisá tu internet e intentá nuevamente.');
    }

    if (r.statusCode >= 200 && r.statusCode < 300) return r;

    String code = 'ERROR';
    String message = 'No se pudo completar la operación.';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      code = (j['code'] as String?) ?? code;
      message = (j['error'] as String?) ?? message;
    } catch (_) {}

    if (auth && retry && r.statusCode == 401 && code == 'TOKEN_EXPIRED' && _refresh != null) {
      await _refreshTokens();
      return _send(method, path, query: query, body: body, auth: auth, retry: false);
    }
    if (auth && _endSessionCodes.contains(code)) await _endSession(message);
    throw ApiException(code, message, r.statusCode);
  }

  Future<Object?> _request(String method, String path,
      {Map<String, String>? query, Object? body, bool auth = true}) async {
    final r = await _send(method, path, query: query, body: body, auth: auth);
    return r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
  }

  Future<Uint8List> _bytes(String path, [Map<String, String>? query]) async =>
      (await _send('GET', path, query: query)).bodyBytes;

  // ---------------- almacenamiento cifrado ----------------

  Future<String?> _read(String k) async {
    try {
      return await _store.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String k, String v) async {
    try {
      await _store.write(key: k, value: v);
    } catch (_) {}
  }

  Future<void> _delete(String k) async {
    try {
      await _store.delete(key: k);
    } catch (_) {}
  }
}

final portal = PortalApi();
