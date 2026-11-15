import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../config/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController(text: 'Abarrotes & Antojitos Los Primos');
  final _phoneController = TextEditingController(text: '55 1234 5678');
  final _addressController = TextEditingController(text: 'Puesto #14, Mercado Local, México');
  final _headerController = TextEditingController(text: '¡Gracias por su compra en el comercio local!');

  bool _useLocalApi = false;
  String _apiStatusMessage = 'Sin comprobar';
  bool _isTestingApi = false;

  @override
  void initState() {
    super.initState();
    _useLocalApi = ApiService.instance.isLocal;
  }

  void _testApiConnection() async {
    setState(() {
      _isTestingApi = true;
      _apiStatusMessage = 'Comprobando respuesta de la API...';
    });

    final ok = await ApiService.instance.checkHealth();

    if (mounted) {
      setState(() {
        _isTestingApi = false;
        _apiStatusMessage = ok
            ? '¡Conectado exitosamente con la API! (${ApiService.instance.baseUrl})'
            : 'No se pudo conectar a la API (${ApiService.instance.baseUrl})';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? AppTheme.primary : Colors.red,
          content: Text(_apiStatusMessage),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del POS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Banner de Modo Demo
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.shade700.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.shade700.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber.shade800, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modo Demo Activo',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Tu punto de venta opera de forma autónoma con base de datos local SQLite y catálogo precargado para micronegocios.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Datos del negocio para tickets
          const Text('Datos del Negocio (Ticket de Impresión):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nombre del Puesto o Tiendita', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: 'Dirección o Ubicación', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _headerController,
            decoration: const InputDecoration(labelText: 'Mensaje de agradecimiento', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),

          // Configuración de API
          const Text('Conexión con el Backend / API:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Usar API Local (Desarrollo por USB)'),
                  subtitle: Text(_useLocalApi ? 'http://localhost:8000/api (vía adb reverse)' : 'https://tabapagos.xalpati.com/api (Producción Hostinger)'),
                  value: _useLocalApi,
                  onChanged: (val) {
                    setState(() {
                      _useLocalApi = val;
                      ApiService.instance.setUseLocal(val);
                    });
                  },
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
                        icon: const Icon(Icons.network_check, color: Colors.white, size: 18),
                        label: _isTestingApi
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Probar Conectividad', style: TextStyle(color: Colors.white)),
                        onPressed: _isTestingApi ? null : _testApiConnection,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _apiStatusMessage,
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Información técnica
          const Center(
            child: Text(
              'Tabapagos POS v1.0.0 • Hecho para Emprendedores Mexicanos\nwww.xalpati.com',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
