import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/constants.dart';
import '../database/db_helper.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  String _baseUrl = AppConstants.productionApiUrl;

  String get baseUrl => _baseUrl;
  bool get isLocal => false;

  void setCustomUrl(String url) {
    if (url.trim().isNotEmpty) {
      _baseUrl = url.trim();
    }
  }

  /// Genera un UUID v4 para identificadores únicos locales
  static String generateUuid() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // Versión 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Variante RFC 4122
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  /// Obtiene los encabezados HTTP comunes con token de autorización Bearer
  Future<Map<String, String>> _authHeaders({String? idempotencyKey}) async {
    final token = await DbHelper.instance.getAuthToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null && idempotencyKey.isNotEmpty) {
      headers['Idempotency-Key'] = idempotencyKey;
    }
    return headers;
  }

  /// Registra una nueva cuenta de comerciante con correo y contraseña
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
    required String installationId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/v1/auth/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'name': name.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'password_confirmation': passwordConfirmation,
          'installation_id': installationId,
        }),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body);
      if (response.statusCode == 201) {
        return {'success': true, 'data': data};
      } else if (response.statusCode == 409) {
        return {
          'success': false,
          'message': 'Este dispositivo ya estuvo vinculado a otra sesión. Intenta registrarte nuevamente.',
        };
      } else {
        String msg = 'Error al registrar la cuenta';
        if (data is Map) {
          if (data['message'] != null) {
            msg = data['message'].toString();
          } else if (data['code'] == 'VALIDATION_FAILED' && data['fields'] is List) {
            final fields = List<String>.from(data['fields']);
            if (fields.contains('email')) {
              msg = 'Este correo electrónico ya está registrado o no es válido.';
            } else if (fields.contains('password')) {
              msg = 'La contraseña debe tener al menos 8 caracteres y coincidir con la confirmación.';
            } else if (fields.contains('installation_id')) {
              msg = 'Identificador del dispositivo no válido.';
            } else if (fields.contains('name')) {
              msg = 'El nombre del negocio o titular es obligatorio.';
            } else {
              msg = 'Datos incompletos o inválidos: ${fields.join(', ')}';
            }
          } else if (data['errors'] != null && data['errors'] is Map) {
            final errMap = data['errors'] as Map;
            if (errMap.isNotEmpty) {
              msg = errMap.values.first[0].toString();
            }
          }
        }
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'No se pudo conectar al servidor: $e'};
    }
  }

  /// Inicia sesión con correo y contraseña
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String installationId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/v1/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim().toLowerCase(),
          'password': password,
          'installation_id': installationId,
        }),
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else if (response.statusCode == 409) {
        return {
          'success': false,
          'message': 'Este dispositivo está vinculado a otra cuenta. Registra una nueva cuenta o contacta a soporte.',
        };
      } else {
        String msg = 'Correo o contraseña incorrectos';
        if (data is Map) {
          if (data['message'] != null) {
            msg = data['message'].toString();
          } else if (data['code'] == 'VALIDATION_FAILED' && data['fields'] is List) {
            final fields = List<String>.from(data['fields']);
            if (fields.contains('email') || fields.contains('password')) {
              msg = 'Correo electrónico o contraseña incorrectos.';
            } else {
              msg = 'Verifica tus credenciales e intenta nuevamente.';
            }
          } else if (data['errors'] != null && data['errors'] is Map) {
            final errMap = data['errors'] as Map;
            if (errMap.isNotEmpty) {
              msg = errMap.values.first[0].toString();
            }
          }
        }
        return {'success': false, 'message': msg};
      }
    } catch (e) {
      return {'success': false, 'message': 'No se pudo conectar al servidor: $e'};
    }
  }

  /// Actualiza el push token FCM del dispositivo actual en la API
  Future<bool> updatePushToken(String pushToken) async {
    try {
      final headers = await _authHeaders();
      if (!headers.containsKey('Authorization')) return false;

      final response = await http.put(
        Uri.parse('$baseUrl/v1/devices/current/push-token'),
        headers: headers,
        body: jsonEncode({'push_token': pushToken}),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Solicita un intento de cobro CoDi real en la nube a través de Pey
  Future<Map<String, dynamic>?> createPaymentAttempt({
    required String localSaleId,
    required String origin, // 'CATALOG' | 'DIRECT'
    required int amountMinor, // en centavos (ej: 15.00 -> 1500)
    required String concept,
    String method = 'CODI_QR',
    String? phone,
  }) async {
    try {
      final idemKey = generateUuid();
      final headers = await _authHeaders(idempotencyKey: idemKey);
      if (!headers.containsKey('Authorization')) return null;

      final bodyMap = <String, dynamic>{
        'local_sale_id': localSaleId,
        'origin': origin,
        'amount_minor': amountMinor,
        'method': method,
        'concept': concept,
      };

      if (method == 'CODI_QR') {
        bodyMap['qr_mode'] = 'per_sale';
      } else if (method == 'CODI_PUSH') {
        if (phone != null && phone.trim().isNotEmpty) {
          bodyMap['phone'] = phone.trim();
        }
      }

      final response = await http.post(
        Uri.parse('$baseUrl/v1/payment-attempts'),
        headers: headers,
        body: jsonEncode(bodyMap),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('createPaymentAttempt HTTP ${response.statusCode}: ${response.body}');
        try {
          return jsonDecode(response.body) as Map<String, dynamic>;
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('createPaymentAttempt exception: $e');
    }
    return null;
  }

  /// Envía la confirmación durable de recepción (ACK) de un evento push (ADR-002)
  Future<bool> ackEvent({
    required String eventId,
    required String deliveryId,
    String result = 'APPLIED', // 'APPLIED' | 'STORED_FOR_REVIEW'
  }) async {
    try {
      final headers = await _authHeaders();
      if (!headers.containsKey('Authorization')) return false;

      final response = await http.post(
        Uri.parse('$baseUrl/v1/events/ack'),
        headers: headers,
        body: jsonEncode({
          'event_id': eventId,
          'delivery_id': deliveryId,
          'result': result,
        }),
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Registra una cuenta bancaria para cobros CoDi en el backend
  Future<Map<String, dynamic>?> registerBankAccount({
    required String alias,
    required String name,
    required String clabe,
    required String entity,
  }) async {
    try {
      final idemKey = 'clabe_${clabe.hashCode}';
      final headers = await _authHeaders(idempotencyKey: idemKey);

      final response = await http.post(
        Uri.parse('$baseUrl/v1/bank-account'),
        headers: headers,
        body: jsonEncode({
          'alias': alias,
          'name': name,
          'clabe': clabe,
          'entity': entity,
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  /// Consulta el estado actual de la cuenta bancaria en la API
  Future<Map<String, dynamic>?> getBankAccount() async {
    try {
      final headers = await _authHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/v1/bank-account'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }

  /// Solicita refrescar el estado de la cuenta con Banxico/Pey
  Future<bool> refreshBankAccount() async {
    try {
      final headers = await _authHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/v1/bank-account/refresh'),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Verifica el estado de salud y conectividad de la API en la nube
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/v1/downloads/meta'),
      ).timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      try {
        final fallback = await http.post(
          Uri.parse('$baseUrl/v1/auth/login'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 4));
        return fallback.statusCode == 422;
      } catch (_) {
        return false;
      }
    }
  }
}
