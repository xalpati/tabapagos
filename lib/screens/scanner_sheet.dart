import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/audio_service.dart';
import '../database/db_helper.dart';
import '../models/product.dart';
import '../config/theme.dart';

class ScannerSheet extends StatefulWidget {
  final Function(Product) onProductScanned;
  final Function(String barcode)? onUnknownBarcode;

  const ScannerSheet({
    super.key,
    required this.onProductScanned,
    this.onUnknownBarcode,
  });

  @override
  State<ScannerSheet> createState() => _ScannerSheetState();
}

class _ScannerSheetState extends State<ScannerSheet> {
  late MobileScannerController controller;
  bool isTorchOn = false;
  String? lastScannedBarcode;
  DateTime? lastScanTime;
  String? lastScannedName;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) async {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    // Evitar lecturas duplicadas en ráfaga (debounce 1.2 segundos para el mismo código)
    final now = DateTime.now();
    if (lastScannedBarcode == rawValue &&
        lastScanTime != null &&
        now.difference(lastScanTime!).inMilliseconds < 1200) {
      return;
    }

    lastScannedBarcode = rawValue;
    lastScanTime = now;

    // 1. Emitir sonido de BIP instantáneo y háptico
    await AudioService.playScanBeep();

    // 2. Buscar producto en la base de datos local
    final product = await DbHelper.instance.getProductByBarcode(rawValue);

    if (mounted) {
      if (product != null) {
        setState(() {
          lastScannedName = '${product.name} - \$${product.price.toStringAsFixed(2)}';
        });
        widget.onProductScanned(product);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.primary,
            duration: const Duration(seconds: 1),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '¡Agregado!: ${product.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(
                  '\$${product.price.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.yellowAccent),
                ),
              ],
            ),
          ),
        );
      } else {
        setState(() {
          lastScannedName = 'Código no registrado: $rawValue';
        });
        if (widget.onUnknownBarcode != null) {
          widget.onUnknownBarcode!(rawValue);
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.amber.shade900,
              content: Text('Código "$rawValue" no encontrado en tu catálogo'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Barra superior de controles del escáner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: AppTheme.primaryLight, size: 28),
                    SizedBox(width: 8),
                    Text(
                      'Lector de Código de Barras',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isTorchOn ? Icons.flash_on : Icons.flash_off,
                        color: isTorchOn ? Colors.yellow : Colors.white70,
                      ),
                      onPressed: () async {
                        await controller.toggleTorch();
                        setState(() {
                          isTorchOn = !isTorchOn;
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Visor de Cámara con marco guía
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                MobileScanner(
                  controller: controller,
                  onDetect: _handleBarcode,
                ),
                // Marco delimitador de lectura
                Container(
                  width: 280,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.primaryLight, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                // Línea láser roja animada o indicativa
                Container(
                  width: 260,
                  height: 2,
                  color: Colors.redAccent.withOpacity(0.8),
                ),
              ],
            ),
          ),

          // Barra inferior con información del último artículo escaneado
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF0F172A),
            child: Column(
              children: [
                if (lastScannedName != null) ...[
                  Text(
                    lastScannedName!,
                    style: const TextStyle(
                      color: AppTheme.primaryLight,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'Apunta la cámara al código de barras del producto. Se emitirá un "bip" y se sumará al ticket en vivo.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
