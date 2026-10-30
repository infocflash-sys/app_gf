import 'package:flutter/services.dart';

const _channel = MethodChannel('com.grupoflash.portal/app');

/// Manda la app a segundo plano (no la cierra): al volver a abrirla queda donde estaba.
Future<void> minimizeApp() async {
  try {
    await _channel.invokeMethod<bool>('minimize');
  } catch (_) {
    await SystemNavigator.pop(); // fuera de Android no existe el canal
  }
}
