import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/constants.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  String _baseUrl = AppConstants.productionApiUrl;
  bool _useLocal = false;

  String get baseUrl => _useLocal ? AppConstants.localApiUrl : _baseUrl;
  bool get isLocal => _useLocal;

  void setUseLocal(bool useLocal) {
    _useLocal = useLocal;
  }

  void setCustomUrl(String url) {
    _baseUrl = url.trim();
  }

  /// Verifica el estado de salud y conectividad de la API
  Future<bool> checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/v1/health'),
      ).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      try {
        final fallback = await http.post(
          Uri.parse('$baseUrl/v1/auth/google'),
          headers: {'Accept': 'application/json'},
        ).timeout(const Duration(seconds: 3));
        return fallback.statusCode == 422; // 422 significa que la API de Laravel respondió activamente
      } catch (_) {
        return false;
      }
    }
  }

  /// Registra un intento de pago en la API para control y auditoría
  Future<Map<String, dynamic>?> registerPaymentAttempt({
    required String deviceId,
    required double amount,
    required String method,
    required String reference,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/v1/payment-attempts'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-Device-Id': deviceId,
        },
        body: jsonEncode({
          'amount': amount,
          'method': method,
          'reference': reference,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      }
    } catch (_) {}
    return null;
  }
}
