import 'package:flutter/services.dart';

/// Puente con el servicio nativo (Android) que mantiene viva la app mientras
/// analiza y muestra el progreso en una notificacion. Solo se usa durante un
/// analisis: se inicia al empezar y se detiene al terminar.
class BackgroundService {
  static const _channel = MethodChannel('aztra/analysis_service');

  static Future<bool> start({
    required String title,
    required String text,
    int progress = -1,
    int max = 0,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('start', {
        'title': title,
        'text': text,
        'progress': progress,
        'max': max,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> update({
    required String title,
    required String text,
    required int progress,
    required int max,
  }) async {
    try {
      await _channel.invokeMethod<bool>('update', {
        'title': title,
        'text': text,
        'progress': progress,
        'max': max,
      });
    } catch (_) {}
  }

  /// Quita la notificacion de progreso y avisa que termino.
  static Future<void> finish({
    required String title,
    required String text,
  }) async {
    try {
      await _channel.invokeMethod<bool>('finish', {
        'title': title,
        'text': text,
      });
    } catch (_) {}
  }

  /// Detiene el servicio sin avisar (cuando tu cancelas).
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<bool>('stop');
    } catch (_) {}
  }

  /// Manda la app al fondo sin cerrarla (para que el analisis siga).
  static Future<void> moveToBack() async {
    try {
      await _channel.invokeMethod<bool>('moveToBack');
    } catch (_) {}
  }
}
