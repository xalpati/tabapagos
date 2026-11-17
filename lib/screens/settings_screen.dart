import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../database/db_helper.dart';
import '../config/theme.dart';
import 'bank_account_screen.dart';
import 'printer_settings_screen.dart';

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

  String? _logoPath;
  int _feedLines = 3;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final name = await DbHelper.instance.getSetting('business_name', defaultValue: 'Abarrotes & Antojitos Los Primos');
    final phone = await DbHelper.instance.getSetting('business_phone', defaultValue: '55 1234 5678');
    final address = await DbHelper.instance.getSetting('business_address', defaultValue: 'Puesto #14, Mercado Local, México');
    final header = await DbHelper.instance.getSetting('ticket_header', defaultValue: '¡Gracias por su compra en el comercio local!');
    final logo = await DbHelper.instance.getLogoPath();
    final lines = await DbHelper.instance.getFeedLines();

    if (mounted) {
      setState(() {
        _nameController.text = name ?? '';
        _phoneController.text = phone ?? '';
        _addressController.text = address ?? '';
        _headerController.text = header ?? '';
        _logoPath = logo;
        _feedLines = lines;
        _isLoading = false;
      });
    }
  }

  Future<void> _pickLogo(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );

      if (picked != null) {
        await DbHelper.instance.setLogoPath(picked.path);
        setState(() {
          _logoPath = picked.path;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppTheme.primary,
              content: Text('Logotipo del negocio guardado. Se imprimirá en los tickets.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Error al seleccionar logotipo: $e'),
          ),
        );
      }
    }
  }

  Future<void> _removeLogo() async {
    await DbHelper.instance.setLogoPath('');
    setState(() {
      _logoPath = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logotipo retirado del ticket.'),
        ),
      );
    }
  }

  Future<void> _saveBusinessInfo() async {
    await DbHelper.instance.setSetting('business_name', _nameController.text.trim());
    await DbHelper.instance.setSetting('business_phone', _phoneController.text.trim());
    await DbHelper.instance.setSetting('business_address', _addressController.text.trim());
    await DbHelper.instance.setSetting('ticket_header', _headerController.text.trim());
    await DbHelper.instance.setFeedLines(_feedLines);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.primary,
          content: Text('Ajustes y datos del negocio guardados correctamente.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración del POS'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Accesos rápidos de hardware y finanzas
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2FE),
                    child: Icon(Icons.print, color: Color(0xFF0284C7)),
                  ),
                  title: const Text('Registrar Impresora Térmica (80mm)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Vincular impresora Bluetooth, calibrar y autocorte'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFECFDF5),
                    child: Icon(Icons.account_balance, color: Color(0xFF059669)),
                  ),
                  title: const Text('Mi Cuenta Bancaria (CoDi)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Registrar CLABE de 18 dígitos para recibir pagos SPEI/CoDi'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const BankAccountScreen()));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Logotipo del negocio para impresión en tickets
          const Text('Logotipo del Negocio (Ticket Térmico):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_logoPath != null && File(_logoPath!).existsSync()) ...[
                    Row(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.file(
                              File(_logoPath!),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Logotipo Activo',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Se imprimirá centrado al inicio de cada ticket térmico.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    icon: const Icon(Icons.photo_library, size: 16),
                                    label: const Text('Cambiar', style: TextStyle(fontSize: 12)),
                                    onPressed: () => _pickLogo(ImageSource.gallery),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                                    icon: const Icon(Icons.delete_outline, size: 16),
                                    label: const Text('Quitar', style: TextStyle(fontSize: 12)),
                                    onPressed: _removeLogo,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                          ),
                          child: const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sin logotipo asignado',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                'Agrega una imagen o logo para personalizar tus recibos.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.secondary),
                          foregroundColor: AppTheme.secondary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('Seleccionar Logotipo de Galería'),
                        onPressed: () => _pickLogo(ImageSource.gallery),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Opciones de Formato de Ticket y Separación de Papel
          const Text('Opciones de Separación y Corte:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Líneas vacías al final del ticket',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              'Separación de papel antes del corte automático.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$_feedLines líneas',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _feedLines.toDouble(),
                    min: 0,
                    max: 8,
                    divisions: 8,
                    activeColor: AppTheme.primary,
                    label: '$_feedLines líneas vacías',
                    onChanged: (val) {
                      setState(() {
                        _feedLines = val.round();
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0 (Corte al ras)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      Text('3 (Recomendado)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      Text('8 (Separación amplia)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
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
            decoration: const InputDecoration(labelText: 'Teléfono de Contacto', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _headerController,
            decoration: const InputDecoration(labelText: 'Mensaje de agradecimiento en ticket', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('Guardar Datos del Negocio', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _saveBusinessInfo,
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
