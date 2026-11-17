import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/printer_service.dart';
import '../services/audio_service.dart';
import '../database/db_helper.dart';
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
  bool _isPrinting = false;
  String? _selectedMac;
  String? _savedPrinterName;
  bool _isConnected = false;
  bool _permissionGranted = true;
  bool _bluetoothEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSavedPrinterAndDevices();
  }

  Future<void> _loadSavedPrinterAndDevices() async {
    setState(() => _isLoading = true);

    // 1. Cargar impresora guardada en base de datos local
    final saved = await DbHelper.instance.getSavedPrinter();
    if (saved != null) {
      _selectedMac = saved['mac'];
      _savedPrinterName = saved['name'];
    } else {
      _selectedMac = null;
      _savedPrinterName = null;
    }

    // 2. Verificar permisos de Bluetooth y si el Bluetooth está encendido
    bool hasPermission = false;
    bool isBtEnabled = false;
    try {
      hasPermission = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      isBtEnabled = await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('Error comprobando estado Bluetooth: $e');
    }

    // 3. Verificar estado de conexión real si hay impresora guardada
    bool connStatus = false;
    if (_selectedMac != null) {
      try {
        connStatus = await PrintBluetoothThermal.connectionStatus;
      } catch (_) {}
    }

    // 4. Obtener lista de dispositivos emparejados en Android
    List<BluetoothInfo> devices = [];
    if (hasPermission && isBtEnabled) {
      devices = await PrinterService.instance.getPairedDevices();
    }

    if (mounted) {
      setState(() {
        _pairedDevices = devices;
        _permissionGranted = hasPermission;
        _bluetoothEnabled = isBtEnabled;
        _isLoading = false;
        _isConnected = connStatus;
      });
    }
  }

  Future<void> _requestBluetoothPermission() async {
    final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
    if (mounted) {
      setState(() => _permissionGranted = granted);
      if (granted) {
        await _loadSavedPrinterAndDevices();
      }
    }
  }

  Future<void> _connectAndRegisterDevice(BluetoothInfo device) async {
    setState(() => _isConnecting = true);

    final success = await PrinterService.instance.autoConnect(targetMac: device.macAdress);

    if (success) {
      // Guardar permanentemente como la impresora del negocio
      await DbHelper.instance.savePrinter(device.macAdress, device.name);
      await AudioService.playSuccessBeep();
    }

    final connStatus = await PrintBluetoothThermal.connectionStatus;

    if (mounted) {
      setState(() {
        _isConnecting = false;
        _selectedMac = device.macAdress;
        _savedPrinterName = device.name;
        _isConnected = connStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? AppTheme.primary : Colors.red,
          content: Text(
            success
                ? '¡Impresora ${device.name} registrada y conectada exitosamente!'
                : 'No se pudo conectar a ${device.name}. Comprueba que esté encendida y con batería.',
          ),
        ),
      );
    }
  }

  Future<void> _disconnectPrinter() async {
    await PrintBluetoothThermal.disconnect;
    final connStatus = await PrintBluetoothThermal.connectionStatus;

    if (mounted) {
      setState(() {
        _isConnected = connStatus;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresora desconectada.'),
        ),
      );
    }
  }

  Future<void> _forgetPrinter() async {
    await PrintBluetoothThermal.disconnect;
    await DbHelper.instance.forgetPrinter();
    PrinterService.instance.isConnected = false;
    PrinterService.instance.connectedMac = null;

    if (mounted) {
      setState(() {
        _selectedMac = null;
        _savedPrinterName = null;
        _isConnected = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impresora desvinculada del negocio.'),
        ),
      );
    }
  }

  Future<void> _printTestTicket() async {
    setState(() => _isPrinting = true);

    final printerName = _savedPrinterName ?? 'BlueTooth Printer';
    final success = await PrinterService.instance.printTestTicket(printerName: printerName);

    if (mounted) {
      setState(() => _isPrinting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: success ? AppTheme.primary : Colors.red,
          content: Text(
            success
                ? '¡Ticket de prueba de 80mm con autocorte impreso con éxito!'
                : 'Error al enviar impresión. Verifica que la impresora esté encendida y conectada.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Impresora (80mm)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Buscar dispositivos',
            onPressed: _loadSavedPrinterAndDevices,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStatusBanner(),
                if (!_permissionGranted) ...[
                  const SizedBox(height: 12),
                  _buildPermissionBanner(),
                ],
                if (!_bluetoothEnabled) ...[
                  const SizedBox(height: 12),
                  _buildBluetoothDisabledBanner(),
                ],
                const SizedBox(height: 20),
                _buildInstructionsCard(),
                const SizedBox(height: 20),
                _buildDeviceListHeader(),
                const SizedBox(height: 10),
                _buildDeviceList(),
                const SizedBox(height: 24),
                _buildPrintTestButton(),
              ],
            ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade700, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.security, color: Colors.amber.shade800, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Permiso de Bluetooth Requerido',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Android 12+ requiere permiso para detectar dispositivos cercanos.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: _requestBluetoothPermission,
            child: const Text('Permitir'),
          ),
        ],
      ),
    );
  }

  Widget _buildBluetoothDisabledBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade400, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(Icons.bluetooth_disabled, color: Colors.red.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bluetooth Desactivado',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Enciende el Bluetooth en los Ajustes de tu teléfono para buscar y conectar tu impresora térmica.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final hasSaved = _savedPrinterName != null && _selectedMac != null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _isConnected
            ? AppTheme.primary.withOpacity(0.12)
            : (hasSaved ? Colors.amber.withOpacity(0.08) : Colors.grey.withOpacity(0.12)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected
              ? AppTheme.primary
              : (hasSaved ? Colors.amber.shade700 : Colors.grey.shade400),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isConnected
                  ? AppTheme.primary
                  : (hasSaved ? Colors.amber.shade700 : Colors.grey.shade600),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.print, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isConnected
                          ? 'Impresora Conectada'
                          : (hasSaved ? 'Impresora Desconectada' : 'Sin Impresora Vinculada'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isConnected
                            ? AppTheme.primary
                            : (hasSaved ? Colors.amber.shade900 : Colors.grey.shade800),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isConnected
                            ? Colors.greenAccent.shade700
                            : (hasSaved ? Colors.amber.shade700 : Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hasSaved
                      ? '$_savedPrinterName (${_selectedMac!})'
                      : 'Ninguna impresora vinculada',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Formato: Papel térmico ancho de 80 mm con autocorte ESC/POS',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (hasSaved) ...[
            if (_isConnected)
              IconButton(
                icon: const Icon(Icons.link_off, color: Colors.red),
                tooltip: 'Desconectar',
                onPressed: _disconnectPrinter,
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              tooltip: 'Olvidar impresora',
              onPressed: _forgetPrinter,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.blue.shade50.withOpacity(0.5),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue, size: 20),
                SizedBox(width: 8),
                Text(
                  '¿Cómo conectar tu impresora térmica?',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              '1. Enciende tu impresora térmica Bluetooth.\n'
              '2. Verifica que esté vinculada en los Ajustes de Bluetooth de tu teléfono Android (PIN habitual: 0000 o 1234).\n'
              '3. En la lista de abajo, toca "Vincular y Conectar" para que Tabapagos tome el control de impresión y autocorte.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceListHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'Impresoras y Dispositivos Detectados:',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Actualizar'),
          onPressed: _loadSavedPrinterAndDevices,
        ),
      ],
    );
  }

  Widget _buildDeviceList() {
    if (_pairedDevices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Column(
          children: [
            Icon(Icons.bluetooth_searching, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No se detectaron dispositivos Bluetooth vinculados',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            SizedBox(height: 6),
            Text(
              'Abre los Ajustes de Bluetooth de Android, vincula tu impresora y pulsa "Actualizar".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _pairedDevices.map((dev) {
        final isSelected = dev.macAdress == _selectedMac;
        final isDeviceConnected = isSelected && _isConnected;
        final isRecommended = dev.name.toLowerCase().contains('printer') || dev.macAdress == AppConstants.defaultPrinterMac;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDeviceConnected
                  ? AppTheme.primary
                  : (isSelected ? Colors.amber.shade700 : Colors.grey.shade300),
              width: isDeviceConnected || isSelected ? 2 : 1,
            ),
            color: isDeviceConnected
                ? AppTheme.primary.withOpacity(0.04)
                : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: isDeviceConnected
                          ? AppTheme.primary
                          : (isRecommended ? Colors.amber.shade700 : Colors.grey.shade200),
                      child: Icon(
                        isRecommended ? Icons.print : Icons.bluetooth,
                        color: isDeviceConnected || isRecommended ? Colors.white : Colors.grey.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  dev.name.isEmpty ? 'Dispositivo Bluetooth' : dev.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isRecommended) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.shade600),
                                  ),
                                  child: Text(
                                    'Recomendada',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text('MAC: ${dev.macAdress}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          if (isDeviceConnected)
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text(
                                '🟢 Conectada y lista para imprimir en 80mm',
                                style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isDeviceConnected)
                      const Icon(Icons.check_circle, color: AppTheme.primary, size: 28),
                  ],
                ),
                if (!isDeviceConnected) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.link, size: 18, color: Colors.white),
                      label: Text(
                        _isConnecting && isSelected ? 'Conectando...' : 'Vincular y Conectar a esta Impresora',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRecommended ? AppTheme.primary : AppTheme.secondary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isConnecting ? null : () => _connectAndRegisterDevice(dev),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPrintTestButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.secondary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        icon: _isPrinting
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.receipt_long, color: Colors.white, size: 24),
        label: Text(
          _isPrinting ? 'Enviando Impresión...' : 'Imprimir Ticket de Calibración (80mm + Autocorte)',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        onPressed: _isPrinting ? null : _printTestTicket,
      ),
    );
  }
}
