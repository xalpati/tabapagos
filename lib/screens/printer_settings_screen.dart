import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/printer_service.dart';
import '../services/audio_service.dart';
import '../config/theme.dart';
import '../config/constants.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<BluetoothInfo> _pairedDevices = [];
  bool _isLoading = true;
  bool _isConnecting = false;
  String? _selectedMac;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    final devices = await PrinterService.instance.getPairedDevices();
    final connectedStatus = await PrintBluetoothThermal.connectionStatus;

    if (mounted) {
      setState(() {
        _pairedDevices = devices;
        _isLoading = false;
        if (connectedStatus && PrinterService.instance.connectedMac != null) {
          _selectedMac = PrinterService.instance.connectedMac;
        } else if (devices.isNotEmpty) {
          // Preseleccionar "BlueTooth Printer" si existe
          final match = devices.firstWhere(
            (d) => d.name.toLowerCase().contains('printer') || d.macAdress == AppConstants.defaultPrinterMac,
            orElse: () => devices.first,
          );
          _selectedMac = match.macAdress;
        }
      });
    }
  }

  Future<void> _connectToDevice(BluetoothInfo device) async {
    setState(() => _isConnecting = true);
    final success = await PrinterService.instance.autoConnect(targetMac: device.macAdress);
    await AudioService.playSuccessBeep();

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _selectedMac = device.macAdress;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? AppTheme.primary : Colors.red,
          content: Text(success ? '¡Conectado exitosamente a ${device.name}!' : 'Error al conectar con ${device.name}'),
        ),
      );
    }
  }

  Future<void> _printTest() async {
    final success = await PrinterService.instance.printTestTicket(
      printerName: _pairedDevices.firstWhere((d) => d.macAdress == _selectedMac, orElse: () => BluetoothInfo(name: 'BlueTooth Printer', macAdress: '')).name,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? AppTheme.primary : Colors.red,
          content: Text(success ? '¡Ticket de prueba y autocorte enviados con éxito!' : 'No se pudo imprimir el ticket de prueba'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Impresora Bluetooth (80mm)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar lista',
            onPressed: _loadDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tarjeta de Estado
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: PrinterService.instance.isConnected
                          ? AppTheme.primary.withOpacity(0.12)
                          : Colors.grey.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: PrinterService.instance.isConnected ? AppTheme.primary : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.print,
                          size: 36,
                          color: PrinterService.instance.isConnected ? AppTheme.primary : Colors.grey,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                PrinterService.instance.isConnected ? 'Impresora Conectada' : 'Impresora Desconectada',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Formato: Papel térmico 80 mm con autocorte',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text(
                    'Dispositivos Bluetooth Vinculados en tu Teléfono:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 10),

                  Expanded(
                    child: _pairedDevices.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay impresoras Bluetooth vinculadas.\nEnciende tu impresora y emparéjala desde Ajustes de Bluetooth de Android.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _pairedDevices.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final dev = _pairedDevices[index];
                              final isCurrent = dev.macAdress == _selectedMac;

                              return Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isCurrent ? AppTheme.primary : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: ListTile(
                                  leading: const Icon(Icons.bluetooth),
                                  title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(dev.macAdress),
                                  trailing: isCurrent && PrinterService.instance.isConnected
                                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                                      : ElevatedButton(
                                          child: const Text('Conectar'),
                                          onPressed: _isConnecting ? null : () => _connectToDevice(dev),
                                        ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Botón de prueba
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
                      icon: const Icon(Icons.receipt, color: Colors.white),
                      label: const Text(
                        'Imprimir Ticket de Prueba (80mm + Autocorte)',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _printTest,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
