import 'package:flutter/services.dart';

class AudioService {
  static const MethodChannel _channel = MethodChannel('com.xalpati.tabapagos/native');

  /// Emite un sonido de 'bip' corto de confirmación al escanear un código de barras
  static Future<void> playScanBeep() async {
    try {
      await _channel.invokeMethod('beep');
    } catch (_) {
      // Fallback a feedback del sistema si el canal nativo fallara
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Emite un tono de éxito al completar un cobro
  static Future<void> playSuccessBeep() async {
    try {
      await _channel.invokeMethod('beepSuccess');
    } catch (_) {
      HapticFeedback.heavyImpact();
    }
  }
}
