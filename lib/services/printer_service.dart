import 'dart:io';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import '../models/sale.dart';
import '../models/business_profile.dart';
import '../database/db_helper.dart';
import '../config/constants.dart';

class PrinterService {
  static final PrinterService instance = PrinterService._internal();
  PrinterService._internal();

  bool isConnected = false;
  String? connectedMac;

  /// Obtiene los dispositivos Bluetooth emparejados en el teléfono
  Future<List<BluetoothInfo>> getPairedDevices() async {
    try {
      // Solicitar y comprobar permisos de Bluetooth en Android 12+
      final bool hasPermission = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!hasPermission) {
        debugPrint('Permisos de Bluetooth no concedidos todavía');
        return [];
      }

      // Comprobar si Bluetooth está encendido
      final bool isEnabled = await PrintBluetoothThermal.bluetoothEnabled;
      if (!isEnabled) {
        debugPrint('Bluetooth apagado en el teléfono');
        return [];
      }

      final List<BluetoothInfo> list = await PrintBluetoothThermal.pairedBluetooths;
      return list;
    } catch (e) {
      debugPrint('Error al obtener lista de Bluetooth emparejados: $e');
      return [];
    }
  }

  /// Conecta automáticamente con la impresora "BlueTooth Printer" o una MAC dada
  Future<bool> autoConnect({String? targetMac}) async {
    try {
      final isConn = await PrintBluetoothThermal.connectionStatus;
      if (isConn) {
        isConnected = true;
        return true;
      }

      final devices = await getPairedDevices();
      BluetoothInfo? target;

      if (targetMac != null) {
        target = devices.cast<BluetoothInfo?>().firstWhere(
          (d) => d?.macAdress == targetMac,
          orElse: () => null,
        );
      }

      target ??= devices.cast<BluetoothInfo?>().firstWhere(
        (d) => d?.name.toLowerCase().contains('printer') == true ||
               d?.macAdress == AppConstants.defaultPrinterMac,
        orElse: () => null,
      );

      if (target != null) {
        final result = await PrintBluetoothThermal.connect(macPrinterAddress: target.macAdress);
        isConnected = result;
        if (result) connectedMac = target.macAdress;
        return result;
      }

      return false;
    } catch (e) {
      isConnected = false;
      return false;
    }
  }

  /// Imprime el ticket de venta en 80mm con autocorte
  Future<bool> printSaleTicket(Sale sale, {BusinessProfile? profile, String? codiQrData}) async {
    try {
      final connected = await autoConnect(targetMac: connectedMac);
      if (!connected) return false;

      final p = profile ?? BusinessProfile();
      final profileGenerator = await CapabilityProfile.load();
      // Generador para papel de 80mm (ancho amplio con 48 caracteres por línea)
      final generator = Generator(PaperSize.mm80, profileGenerator);

      List<int> bytes = [];

      // Inicializar y resetear estilo
      bytes += generator.reset();

      // Si existe logotipo del negocio configurado, imprimirlo al inicio
      final logoPath = await DbHelper.instance.getLogoPath();
      if (logoPath != null && logoPath.isNotEmpty && File(logoPath).existsSync()) {
        try {
          final bytesImg = await File(logoPath).readAsBytes();
          final decoded = img.decodeImage(bytesImg);
          if (decoded != null) {
            // Ancho recomendado para papel de 80mm: máx 384 px
            final resized = decoded.width > 384
                ? img.copyResize(decoded, width: 384)
                : decoded;
            bytes += generator.imageRaster(resized, align: PosAlign.center);
            bytes += generator.emptyLines(1);
          }
        } catch (e) {
          debugPrint('Error al imprimir logotipo en ticket: $e');
        }
      }

      // Encabezado
      bytes += generator.text(
        p.name,
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ),
      );

      if (p.address.isNotEmpty) {
        bytes += generator.text(
          p.address,
          styles: const PosStyles(align: PosAlign.center),
        );
      }

      if (p.phone.isNotEmpty) {
        bytes += generator.text(
          'Tel: ${p.phone}',
          styles: const PosStyles(align: PosAlign.center),
        );
      }

      if (p.rfc.isNotEmpty) {
        bytes += generator.text(
          'RFC: ${p.rfc}',
          styles: const PosStyles(align: PosAlign.center),
        );
      }

      bytes += generator.hr(ch: '=');

      // Folio y Fecha
      final dateFormatted = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(sale.createdAt));
      bytes += generator.text('Folio: ${sale.folio}', styles: const PosStyles(bold: true));
      bytes += generator.text('Fecha: $dateFormatted');
      bytes += generator.hr(ch: '-');

      // Cabecera de columnas para 80mm (Total 48 caracteres aprox)
      bytes += generator.row([
        PosColumn(text: 'Cant', width: 2, styles: const PosStyles(bold: true)),
        PosColumn(text: 'Producto', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: 'P.Unit', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
        PosColumn(text: 'Total', width: 2, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
      bytes += generator.hr(ch: '-');

      // Renglones de venta
      for (var item in sale.items) {
        bytes += generator.row([
          PosColumn(text: '${item.quantity}x', width: 2),
          PosColumn(text: item.productName, width: 6),
          PosColumn(text: '\$${item.price.toStringAsFixed(2)}', width: 2, styles: const PosStyles(align: PosAlign.right)),
          PosColumn(text: '\$${item.subtotal.toStringAsFixed(2)}', width: 2, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.hr(ch: '=');

      // Totales
      bytes += generator.row([
        PosColumn(text: 'TOTAL:', width: 6, styles: const PosStyles(bold: true, height: PosTextSize.size2)),
        PosColumn(
          text: '\$${sale.total.toStringAsFixed(2)} MXN',
          width: 6,
          styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2),
        ),
      ]);

      bytes += generator.emptyLines(1);

      // Forma de pago y cambio
      final isCodiPush = sale.paymentMethod == 'CODI_PUSH';
      final isCodi = sale.paymentMethod.startsWith('CODI');
      bytes += generator.text('Forma de pago: ${isCodiPush ? 'CoDi Push (Celular)' : sale.paymentMethod}', styles: const PosStyles(bold: true));
      if (sale.paymentMethod == 'EFECTIVO') {
        bytes += generator.text('Recibido: \$${sale.amountPaid.toStringAsFixed(2)}');
        bytes += generator.text('Cambio:   \$${sale.change.toStringAsFixed(2)}', styles: const PosStyles(bold: true));
      } else if (isCodi) {
        bytes += generator.text(
          isCodiPush ? 'Cobro CoDi por Notificación Celular' : 'Cobro Digital CoDi (Banxico)',
          styles: const PosStyles(bold: true),
        );
        if (sale.peyPaymentId != null) {
          bytes += generator.text('ID Transacción: ${sale.peyPaymentId}');
        }
      }

      // Código QR en ticket si fue CoDi QR
      if (sale.paymentMethod == 'CODI' && codiQrData != null && codiQrData.isNotEmpty) {
        bytes += generator.emptyLines(1);
        bytes += generator.text('Comprobante CoDi:', styles: const PosStyles(align: PosAlign.center, bold: true));
        bytes += generator.qrcode(codiQrData, size: QRSize.size4);
      }

      bytes += generator.emptyLines(1);
      bytes += generator.text(p.ticketHeader, styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(p.ticketFooter, styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('Generado por Tabapagos POS', styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));

      // Alimentación de papel antes del corte (configurable por el usuario)
      final feedLines = await DbHelper.instance.getFeedLines();
      if (feedLines > 0) {
        bytes += generator.feed(feedLines);
      }

      // Comando nativo ESC/POS de Autocorte total (GS V 0 = 0x1D, 0x56, 0x00)
      bytes += [0x1D, 0x56, 0x00];

      // Enviar bytes a la impresora
      final result = await PrintBluetoothThermal.writeBytes(bytes);
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Imprime un ticket de prueba para calibrar el ancho de 80mm y verificar el autocorte
  Future<bool> printTestTicket({String? printerName}) async {
    try {
      final connected = await autoConnect(targetMac: connectedMac);
      if (!connected) return false;

      final profileGenerator = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profileGenerator);
      List<int> bytes = [];

      // Logotipo si existe
      final testLogoPath = await DbHelper.instance.getLogoPath();
      if (testLogoPath != null && testLogoPath.isNotEmpty && File(testLogoPath).existsSync()) {
        try {
          final bytesImg = await File(testLogoPath).readAsBytes();
          final decoded = img.decodeImage(bytesImg);
          if (decoded != null) {
            final resized = decoded.width > 384 ? img.copyResize(decoded, width: 384) : decoded;
            bytes += generator.imageRaster(resized, align: PosAlign.center);
            bytes += generator.emptyLines(1);
          }
        } catch (_) {}
      }

      bytes += generator.text(
        'TABAPAGOS POS',
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ),
      );
      bytes += generator.text(
        'Prueba de Impresión 80mm',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.hr(ch: '=');
      bytes += generator.text('Impresora: ${printerName ?? "BlueTooth Printer"}');
      bytes += generator.text('Fecha: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}');
      bytes += generator.text('Ancho de papel: 80 mm (48 columnas)');
      bytes += generator.hr(ch: '-');
      bytes += generator.text('Calibración: ¡Alineación y corte automáticos correctos!');
      bytes += generator.emptyLines(1);
      bytes += generator.qrcode('https://tabapagos.xalpati.com', size: QRSize.size4);
      bytes += generator.emptyLines(1);
      bytes += generator.text('www.xalpati.com', styles: const PosStyles(align: PosAlign.center));
      final feedLines = await DbHelper.instance.getFeedLines();
      if (feedLines > 0) {
        bytes += generator.feed(feedLines);
      }
      // Autocorte
      bytes += [0x1D, 0x56, 0x00];

      return await PrintBluetoothThermal.writeBytes(bytes);
    } catch (e) {
      return false;
    }
  }
}
