import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'audio_service.dart';
import '../database/db_helper.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('FCM background message received: ${message.messageId}');
  await FcmService.instance.processIncomingMessage(message);
}

class FcmService {
  static final FcmService instance = FcmService._internal();
  FcmService._internal();

  final _paymentReceivedController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onPaymentReceived => _paymentReceivedController.stream;

  String? _pushToken;
  String? get pushToken => _pushToken;

  bool _initialized = false;

  /// Inicializa Firebase y los escuchadores de Firebase Cloud Messaging
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;

      // Solicitar permisos en Android 13+
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('FCM Notification permission status: ${settings.authorizationStatus}');

      // Obtener el push token FCM del dispositivo
      _pushToken = await messaging.getToken();
      debugPrint('FCM Push Token: $_pushToken');

      if (_pushToken != null) {
        await syncPushToken();
      }

      // Escuchar renovaciones de token
      messaging.onTokenRefresh.listen((newToken) {
        _pushToken = newToken;
        debugPrint('FCM Token Refreshed: $newToken');
        syncPushToken();
      });

      // Escuchar mensajes push mientras la app está abierta (foreground)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message received: ${message.data}');
        processIncomingMessage(message);
      });

      _initialized = true;
    } catch (e) {
      debugPrint('Error al inicializar FCM: $e');
    }
  }

  /// Sincroniza el push token actual con la API si hay sesión iniciada
  Future<void> syncPushToken() async {
    if (_pushToken == null) return;
    final hasSession = await DbHelper.instance.hasActiveSession();
    if (hasSession) {
      final ok = await ApiService.instance.updatePushToken(_pushToken!);
      debugPrint('FCM Push token synced with Hostinger API: $ok');
    }
  }

  /// Procesa un mensaje push entrante (JWS firmado según ADR-002)
  Future<void> processIncomingMessage(RemoteMessage message) async {
    try {
      final rawEvent = message.data['event']?.toString();
      if (rawEvent == null || rawEvent.isEmpty) return;

      final envelope = _decodeJwsEnvelope(rawEvent);
      if (envelope == null) return;

      final eventId = envelope['event_id']?.toString() ?? '';
      final deliveryId = envelope['delivery_id']?.toString() ?? '';
      final eventType = envelope['event_type']?.toString() ?? '';
      final payload = envelope['payload'] as Map<String, dynamic>? ?? {};

      debugPrint('FCM Event parsed: type=$eventType, delivery=$deliveryId');

      if (eventType == 'payment.received') {
        // 1. Tono sonoro de cobro confirmado
        await AudioService.playSuccessBeep();

        // 2. Notificar a los escuchadores de la interfaz (PaymentModal / PosScreen)
        _paymentReceivedController.add(payload);

        // 3. Emitir acuse de recibo durable (ACK) a la API en Hostinger
        if (eventId.isNotEmpty && deliveryId.isNotEmpty) {
          await ApiService.instance.ackEvent(
            eventId: eventId,
            deliveryId: deliveryId,
            result: 'APPLIED',
          );
        }
      } else if (eventType == 'bank_account.activated') {
        // Actualizar estado de la cuenta en SQLite local
        await DbHelper.instance.saveBankAccount(
          alias: 'Cuenta Principal CoDi',
          holderName: '',
          clabe: '',
          entity: 'PERSON',
          bankName: 'Banco Validado',
          status: 'ACTIVE',
        );

        if (eventId.isNotEmpty && deliveryId.isNotEmpty) {
          await ApiService.instance.ackEvent(
            eventId: eventId,
            deliveryId: deliveryId,
            result: 'APPLIED',
          );
        }
      }
    } catch (e) {
      debugPrint('Error al procesar mensaje push: $e');
    }
  }

  /// Decodifica la carga útil del JWS/JWT firmado sin librerías externas
  Map<String, dynamic>? _decodeJwsEnvelope(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      var payloadB64 = parts[1];
      // Normalizar padding de base64
      while (payloadB64.length % 4 != 0) {
        payloadB64 += '=';
      }
      final decodedBytes = base64Url.decode(payloadB64);
      final jsonStr = utf8.decode(decodedBytes);
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error al decodificar JWS envelope: $e');
      return null;
    }
  }
}
