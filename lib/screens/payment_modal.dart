import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../database/db_helper.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
import '../services/fcm_service.dart';
import '../services/printer_service.dart';
import '../services/pey_service.dart';
import '../config/theme.dart';

class PaymentModal extends StatefulWidget {
  final double total;
  final List<SaleItem> items;
  final VoidCallback onPaymentCompleted;
  final int initialTab;

  const PaymentModal({
    super.key,
    required this.total,
    required this.items,
    required this.onPaymentCompleted,
    this.initialTab = 0,
  });

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _fcmSubscription;
  
  // Estado Efectivo
  double _amountReceived = 0.0;

  // Estado CoDi QR
  bool _isLoadingCodi = false;
  String? _codiQrData;
  String? _codiChargeId;
  String? _codiReference;
  String? _localSaleId;
  bool _isLiveCodi = false;
  String? _codiErrorMessage;
  bool _isDemo = false;

  // Estado CoDi Push (Notificación por Teléfono)
  final TextEditingController _pushPhoneController = TextEditingController();
  bool _isLoadingPush = false;
  bool _isPushSent = false;
  bool _isLiveCodiPush = false;
  String? _pushTransactionId;
  String? _pushCodiId;
  String? _pushErrorMessage;

  // Estado general
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
    _amountReceived = widget.total;

    DbHelper.instance.isDemoSession().then((v) {
      if (mounted) setState(() => _isDemo = v);
    });

    if (widget.initialTab == 1 && _codiQrData == null) {
      _generateCodiCharge();
    }

    _tabController.addListener(() {
      if (_tabController.index == 1 && _codiQrData == null) {
        _generateCodiCharge();
      }
      if (mounted) setState(() {});
    });

    // Escuchar notificaciones push de cobro en tiempo real vía Firebase FCM (ADR-002)
    _fcmSubscription = FcmService.instance.onPaymentReceived.listen((payload) {
      debugPrint('PaymentModal received payment push: $payload');
      final pAttemptId = payload['payment_attempt_id']?.toString();
      final lSaleId = payload['local_sale_id']?.toString();

      if ((_codiChargeId != null && pAttemptId == _codiChargeId) ||
          (_localSaleId != null && lSaleId == _localSaleId)) {
        debugPrint('Push matches active payment attempt! Completing sale automatically.');
        final method = _tabController.index == 2 ? 'CODI_PUSH' : 'CODI';
        _completeSale(method);
      }
    });
  }

  @override
  void dispose() {
    _fcmSubscription?.cancel();
    _pushPhoneController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _formatProviderError(String serverMsg) {
    final lower = serverMsg.toLowerCase();
    if (lower.contains('not active') || lower.contains('pending')) {
      return 'Tu cuenta bancaria está en proceso de validación ante Banxico / Pey (PENDING). En cuanto Banxico confirme la CLABE, podrás emitir cobros reales CoDi.';
    }
    if (lower.contains('cuenta bancaria vinculada')) {
      return 'No tienes una cuenta bancaria vinculada a tu perfil. Registra tu CLABE en Configuración.';
    }
    if (lower.contains('invalid phone') || lower.contains('phone')) {
      return 'El número celular del cliente no es válido para CoDi Banxico (deben ser 10 dígitos numéricos).';
    }
    return serverMsg;
  }

  void _generateCodiCharge() async {
    setState(() {
      _isLoadingCodi = true;
      _codiErrorMessage = null;
    });

    final isDemo = await DbHelper.instance.isDemoSession();
    final hasSession = await DbHelper.instance.hasActiveSession();

    if (hasSession && !isDemo) {
      // 1. Cobro CoDi real en la nube a través de la API en Hostinger y Pey (cuenta del usuario)
      final localSaleId = ApiService.generateUuid();
      _localSaleId = localSaleId;

      try {
        final isDirect = widget.items.length == 1 && widget.items.first.productId == null;
        final attempt = await ApiService.instance.createPaymentAttempt(
          localSaleId: localSaleId,
          origin: isDirect ? 'DIRECT' : 'CATALOG',
          amountMinor: (widget.total * 100).round(),
          concept: 'Consumo Tabapagos POS',
        );

        if (attempt != null && attempt['creation'] != null && attempt['creation']['qrString'] != null) {
          if (mounted) {
            setState(() {
              _isLoadingCodi = false;
              _isLiveCodi = true;
              _codiQrData = attempt['creation']['qrString'];
              _codiChargeId = attempt['id']?.toString();
              _codiReference = attempt['creation']['id']?.toString() ?? localSaleId.substring(0, 8);
              _codiErrorMessage = null;
            });
          }
          return;
        } else {
          // En cuenta real jamás se cae a simulación: se reporta el motivo real
          final serverMsg = attempt?['message']?.toString() ?? 'No se pudo generar el cobro CoDi en Pey / Banxico.';
          final friendlyMsg = _formatProviderError(serverMsg);
          if (mounted) {
            setState(() {
              _isLoadingCodi = false;
              _isLiveCodi = false;
              _codiQrData = null;
              _codiChargeId = null;
              _codiErrorMessage = friendlyMsg;
            });
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingCodi = false;
            _isLiveCodi = false;
            _codiQrData = null;
            _codiChargeId = null;
            _codiErrorMessage = 'Error de conexión con el servidor: $e';
          });
        }
        return;
      }
    }

    // 2. Modo DEMO explícito (únicamente si isDemo es true o no hay sesión iniciada)
    final ref = 'DEMO${Random().nextInt(900000) + 100000}';
    _codiReference = ref;

    final charge = await PeyService.instance.createCodiCharge(
      amount: widget.total,
      reference: ref,
      concept: 'Consumo Tabapagos POS (Demo)',
    );

    if (mounted) {
      setState(() {
        _isLoadingCodi = false;
        _isLiveCodi = false;
        _codiQrData = charge.qrData;
        _codiChargeId = charge.chargeId;
        _codiErrorMessage = null;
      });
    }
  }

  void _sendCodiPush() async {
    final phone = _pushPhoneController.text.trim();
    if (phone.length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(phone)) {
      setState(() {
        _pushErrorMessage = 'Ingresa un número celular válido a 10 dígitos';
      });
      return;
    }

    setState(() {
      _isLoadingPush = true;
      _pushErrorMessage = null;
    });

    FocusScope.of(context).unfocus();

    final isDemo = await DbHelper.instance.isDemoSession();
    final hasSession = await DbHelper.instance.hasActiveSession();

    if (hasSession && !isDemo) {
      // Cuenta real: Envío CoDi Push real a Banxico / Pey vía API
      final localSaleId = ApiService.generateUuid();
      _localSaleId = localSaleId;

      try {
        final isDirect = widget.items.length == 1 && widget.items.first.productId == null;
        final attempt = await ApiService.instance.createPaymentAttempt(
          localSaleId: localSaleId,
          origin: isDirect ? 'DIRECT' : 'CATALOG',
          amountMinor: (widget.total * 100).round(),
          concept: 'Consumo Tabapagos POS',
          method: 'CODI_PUSH',
          phone: phone,
        );

        if (attempt != null && attempt['creation'] != null) {
          if (mounted) {
            setState(() {
              _isLoadingPush = false;
              _isPushSent = true;
              _isLiveCodiPush = true;
              _codiChargeId = attempt['id']?.toString();
              _pushTransactionId = attempt['creation']['transactionId']?.toString();
              _pushCodiId = attempt['creation']['codiId']?.toString();
              _pushErrorMessage = null;
            });
          }
          return;
        } else {
          // En cuenta real jamás simular envío que no ocurrió: mostrar error real
          final serverMsg = attempt?['message']?.toString() ?? 'Error al procesar el requerimiento CoDi en Banxico.';
          final friendlyMsg = _formatProviderError(serverMsg);
          if (mounted) {
            setState(() {
              _isLoadingPush = false;
              _isPushSent = false;
              _pushErrorMessage = friendlyMsg;
            });
          }
          return;
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoadingPush = false;
            _isPushSent = false;
            _pushErrorMessage = 'Error de conexión con el servidor: $e';
          });
        }
        return;
      }
    }

    // Modo DEMO únicamente
    final randomTrx = 'DEMO_TRX${Random().nextInt(900000) + 100000}';
    final randomCodi = 'DEMO_CDI${DateTime.now().millisecondsSinceEpoch}';
    if (mounted) {
      setState(() {
        _isLoadingPush = false;
        _isPushSent = true;
        _isLiveCodiPush = false;
        _codiChargeId = 'LOCAL_${DateTime.now().millisecondsSinceEpoch}';
        _pushTransactionId = randomTrx;
        _pushCodiId = randomCodi;
      });
    }
  }

  double get _change => max(0.0, _amountReceived - widget.total);

  void _setExactAmount() {
    setState(() {
      _amountReceived = widget.total;
    });
  }

  void _addBill(double bill) {
    setState(() {
      if (_amountReceived < widget.total) {
        _amountReceived = bill;
      } else {
        _amountReceived += bill;
      }
    });
  }

  Future<void> _completeSale(String method) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final folio = 'FOL-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      final isCodi = method.startsWith('CODI');
      final sale = Sale(
        folio: folio,
        total: widget.total,
        paymentMethod: method,
        amountPaid: method == 'EFECTIVO' ? _amountReceived : widget.total,
        change: method == 'EFECTIVO' ? _change : 0.0,
        peyPaymentId: isCodi ? (_codiChargeId ?? _pushCodiId) : null,
        createdAt: DateTime.now().toIso8601String(),
        items: widget.items,
      );

      // 1. Guardar en SQLite
      await DbHelper.instance.insertSale(sale);

      // 2. Tono de éxito
      await AudioService.playSuccessBeep();

      // 3. Imprimir ticket en la impresora de 80mm con autocorte si está conectada
      bool printed = false;
      try {
        printed = await PrinterService.instance.printSaleTicket(
          sale,
          codiQrData: method == 'CODI' ? _codiQrData : null,
        );
      } catch (e) {
        debugPrint('Error enviando ticket a impresora: $e');
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onPaymentCompleted();

        _showSuccessDialog(sale, printed: printed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al procesar la venta: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog(Sale sale, {bool printed = false}) {
    final isPush = sale.paymentMethod == 'CODI_PUSH';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppTheme.primary, size: 36),
            SizedBox(width: 12),
            Text('¡Venta Exitosa!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Folio: ${sale.folio}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Total: \$${sale.total.toStringAsFixed(2)} MXN (${isPush ? 'CoDi Push' : sale.paymentMethod})'),
            if (sale.paymentMethod == 'EFECTIVO' && sale.change > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Cambio: \$${sale.change.toStringAsFixed(2)} MXN',
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
            if (isPush && _pushPhoneController.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Teléfono cliente: ${_pushPhoneController.text}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  printed ? Icons.check_circle : Icons.print_disabled,
                  color: printed ? Colors.green : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    printed
                        ? 'Ticket impreso en "BlueTooth Printer" de 80mm con autocorte.'
                        : 'Venta guardada. No se detectó impresora conectada para emitir ticket físico.',
                    style: TextStyle(
                      color: printed ? Colors.green.shade800 : Colors.grey.shade700,
                      fontSize: 12,
                      fontWeight: printed ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Reimprimir'),
            onPressed: () {
              PrinterService.instance.printSaleTicket(sale, codiQrData: _codiQrData);
            },
          ),
          ElevatedButton(
            child: const Text('Nueva Venta'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Barra de arrastre superior
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 16),

          // Total a cobrar en grande
          Text(
            'Total a Cobrar',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${widget.total.toStringAsFixed(2)} MXN',
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),

          // Selector de Método de Pago con 3 Pestañas
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(context).textTheme.bodyLarge?.color,
              tabs: const [
                Tab(
                  icon: Icon(Icons.payments_outlined, size: 22),
                  text: 'Efectivo',
                ),
                Tab(
                  icon: Icon(Icons.qr_code_2, size: 22),
                  text: 'CoDi QR',
                ),
                Tab(
                  icon: Icon(Icons.send_to_mobile, size: 22),
                  text: 'CoDi Push',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Contenido de las pestañas
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCashTab(),
                _buildCodiTab(),
                _buildCodiPushTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Vista de Cobro en Efectivo ---
  Widget _buildCashTab() {
    return Column(
      children: [
        // Botones rápidos de denominaciones de billetes mexicanos
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildQuickButton('Exacto', _setExactAmount, isSpecial: true),
            _buildQuickButton('+\$50', () => _addBill(50)),
            _buildQuickButton('+\$100', () => _addBill(100)),
            _buildQuickButton('+\$200', () => _addBill(200)),
            _buildQuickButton('+\$500', () => _addBill(500)),
          ],
        ),
        const SizedBox(height: 16),

        // Tarjeta de Monto Recibido y Cambio
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Paga con:', style: TextStyle(fontSize: 16)),
                  Text(
                    '\$${_amountReceived.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cambio a devolver:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    '\$${_change.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: _amountReceived >= widget.total ? AppTheme.primary : Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const Spacer(),

        // Botón Cobrar en Efectivo
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _amountReceived >= widget.total && !_isProcessing
                ? () => _completeSale('EFECTIVO')
                : null,
            child: _isProcessing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Completar Cobro e Imprimir Ticket (80mm)'),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onTap, {bool isSpecial = false}) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: isSpecial ? AppTheme.secondary.withOpacity(0.15) : null,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isSpecial ? AppTheme.secondary : null,
        ),
      ),
    );
  }

  Widget _buildCodiModeSelector(int currentTab) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: currentTab == 1 ? AppTheme.primary : Colors.transparent,
                foregroundColor: currentTab == 1 ? Colors.white : Colors.grey.shade800,
                elevation: currentTab == 1 ? 2 : 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.qr_code_2, size: 20, color: currentTab == 1 ? Colors.white : Colors.grey.shade700),
              label: Text(
                'Código QR',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: currentTab == 1 ? Colors.white : Colors.grey.shade800,
                ),
              ),
              onPressed: () {
                _tabController.animateTo(1);
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: currentTab == 2 ? AppTheme.primary : Colors.transparent,
                foregroundColor: currentTab == 2 ? Colors.white : Colors.grey.shade800,
                elevation: currentTab == 2 ? 2 : 0,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.send_to_mobile, size: 20, color: currentTab == 2 ? Colors.white : Colors.grey.shade700),
              label: Text(
                'Solicitud Celular (Push)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                  color: currentTab == 2 ? Colors.white : Colors.grey.shade800,
                ),
              ),
              onPressed: () {
                _tabController.animateTo(2);
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- Vista de Cobro CoDi QR (Pey) ---
  Widget _buildCodiTab() {
    if (_isLoadingCodi) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildCodiModeSelector(1),
            const Spacer(),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Generando código CoDi con Pey Banxico...'),
            const Spacer(),
          ],
        ),
      );
    }

    if (_codiErrorMessage != null && !_isLoadingCodi) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildCodiModeSelector(1),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.shade400, width: 1.5),
              ),
              child: Column(
                children: [
                  Icon(Icons.info_outline_rounded, size: 48, color: Colors.amber.shade900),
                  const SizedBox(height: 12),
                  const Text(
                    'Estado del Cobro CoDi QR',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _codiErrorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar generar QR'),
                    onPressed: _generateCodiCharge,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildCodiModeSelector(1),
        const Text(
          'El cliente debe escanear el QR desde su App de Banco (BBVA, Banorte, Mercado Pago, etc.)',
          style: TextStyle(fontSize: 13, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        // QR CoDi
        if (_codiQrData != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            child: QrImageView(
              data: _codiQrData!,
              version: QrVersions.auto,
              size: 200.0,
              backgroundColor: Colors.white,
            ),
          ),

        const SizedBox(height: 8),
        if (_codiReference != null)
          Text(
            'Ref: $_codiReference',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),

        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isLiveCodi
                ? AppTheme.primary.withOpacity(0.12)
                : (_isDemo ? Colors.amber.withOpacity(0.15) : AppTheme.primary.withOpacity(0.12)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isLiveCodi
                  ? AppTheme.primary.withOpacity(0.3)
                  : (_isDemo ? Colors.amber.shade700.withOpacity(0.3) : AppTheme.primary.withOpacity(0.3)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isLiveCodi ? Icons.sensors : (_isDemo ? Icons.bug_report : Icons.qr_code_2),
                size: 16,
                color: _isLiveCodi ? AppTheme.primary : (_isDemo ? Colors.amber.shade800 : AppTheme.primary),
              ),
              const SizedBox(width: 6),
              Text(
                _isLiveCodi
                    ? 'Esperando pago Banxico por Push FCM...'
                    : (_isDemo ? 'Modo Demostración Local' : 'Código QR CoDi Oficial'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _isLiveCodi ? AppTheme.primary : (_isDemo ? Colors.amber.shade900 : AppTheme.primary),
                ),
              ),
            ],
          ),
        ),

        const Spacer(),

        // Botón Confirmar Pago CoDi
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: _isProcessing
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Confirmar Cobro CoDi e Imprimir Ticket'),
            onPressed: !_isProcessing && _codiQrData != null ? () => _completeSale('CODI') : null,
          ),
        ),
      ],
    );
  }

  // --- Vista de Cobro CoDi Push (Notificación Celular Banxico) ---
  Widget _buildCodiPushTab() {
    if (_isPushSent) {
      return SingleChildScrollView(
        child: Column(
          children: [
            _buildCodiModeSelector(2),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mark_email_read_rounded,
                      size: 44,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '¡Solicitud CoDi Enviada!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Requerimiento enviado a: +52 ${_pushPhoneController.text}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monto: \$${widget.total.toStringAsFixed(2)} MXN',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  if (_pushCodiId != null || _pushTransactionId != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Folio: ${_pushCodiId ?? _pushTransactionId}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isLiveCodiPush
                          ? AppTheme.primary.withOpacity(0.12)
                          : (_isDemo ? Colors.amber.withOpacity(0.15) : AppTheme.primary.withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _isLiveCodiPush
                            ? AppTheme.primary.withOpacity(0.3)
                            : (_isDemo ? Colors.amber.shade700.withOpacity(0.3) : AppTheme.primary.withOpacity(0.3)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isLiveCodiPush ? Icons.sensors : (_isDemo ? Icons.bug_report : Icons.check_circle_outline),
                          size: 16,
                          color: _isLiveCodiPush ? AppTheme.primary : (_isDemo ? Colors.amber.shade800 : AppTheme.primary),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _isLiveCodiPush
                                ? 'Esperando confirmación bancaria (FCM Push)...'
                                : (_isDemo ? 'Modo Demostración Local' : 'Solicitud Enviada a Banxico'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isLiveCodiPush ? AppTheme.primary : (_isDemo ? Colors.amber.shade900 : AppTheme.primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.edit, size: 18),
              label: const Text('Cambiar número celular o reenviar'),
              onPressed: () {
                setState(() {
                  _isPushSent = false;
                });
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline),
                label: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Confirmar Cobro e Imprimir Ticket'),
                onPressed: !_isProcessing ? () => _completeSale('CODI_PUSH') : null,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCodiModeSelector(2),
          const SizedBox(height: 8),
          const Text(
            'Cobro CoDi Directo al Celular',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Ingresa el número celular a 10 dígitos del cliente. Su app bancaria (BBVA, Banorte, Santander, etc.) le mostrará una notificación para autorizar el cobro.',
            style: TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (_pushErrorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade400, width: 1.2),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.amber.shade900, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pushErrorMessage!,
                      style: TextStyle(color: Colors.amber.shade900, fontSize: 13, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _pushPhoneController,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'Teléfono celular del cliente',
              hintText: '55 1234 5678',
              prefixIcon: const Icon(Icons.phone_android, color: AppTheme.primary),
              prefixText: '+52 ',
              prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              counterText: '',
            ),
            onSubmitted: (_) => _sendCodiPush(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              icon: _isLoadingPush
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(
                _isLoadingPush ? 'Enviando a Banxico...' : 'Enviar Requerimiento CoDi al Celular',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: _isLoadingPush ? null : _sendCodiPush,
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined, size: 16, color: Colors.grey),
              SizedBox(width: 6),
              Text(
                'Transacción protegida por SPEI / Banxico',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
