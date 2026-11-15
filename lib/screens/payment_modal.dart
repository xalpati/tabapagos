import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../database/db_helper.dart';
import '../services/audio_service.dart';
import '../services/printer_service.dart';
import '../services/pey_service.dart';
import '../config/theme.dart';

class PaymentModal extends StatefulWidget {
  final double total;
  final List<SaleItem> items;
  final VoidCallback onPaymentCompleted;

  const PaymentModal({
    super.key,
    required this.total,
    required this.items,
    required this.onPaymentCompleted,
  });

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Estado Efectivo
  double _amountReceived = 0.0;

  // Estado CoDi
  bool _isLoadingCodi = false;
  String? _codiQrData;
  String? _codiChargeId;
  String? _codiReference;

  // Estado general
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _amountReceived = widget.total;

    _tabController.addListener(() {
      if (_tabController.index == 1 && _codiQrData == null) {
        _generateCodiCharge();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _generateCodiCharge() async {
    setState(() => _isLoadingCodi = true);
    final ref = 'TABA${Random().nextInt(900000) + 100000}';
    _codiReference = ref;

    final charge = await PeyService.instance.createCodiCharge(
      amount: widget.total,
      reference: ref,
      concept: 'Consumo Tabapagos POS',
    );

    if (mounted) {
      setState(() {
        _isLoadingCodi = false;
        _codiQrData = charge.qrData;
        _codiChargeId = charge.chargeId;
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
      final sale = Sale(
        folio: folio,
        total: widget.total,
        paymentMethod: method,
        amountPaid: method == 'EFECTIVO' ? _amountReceived : widget.total,
        change: method == 'EFECTIVO' ? _change : 0.0,
        peyPaymentId: method == 'CODI' ? _codiChargeId : null,
        createdAt: DateTime.now().toIso8601String(),
        items: widget.items,
      );

      // 1. Guardar en SQLite
      await DbHelper.instance.insertSale(sale);

      // 2. Tono de éxito
      await AudioService.playSuccessBeep();

      // 3. Imprimir ticket en la impresora de 80mm con autocorte
      PrinterService.instance.printSaleTicket(
        sale,
        codiQrData: method == 'CODI' ? _codiQrData : null,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onPaymentCompleted();

        _showSuccessDialog(sale);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al procesar la venta: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSuccessDialog(Sale sale) {
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
            Text('Total: \$${sale.total.toStringAsFixed(2)} MXN (${sale.paymentMethod})'),
            if (sale.paymentMethod == 'EFECTIVO' && sale.change > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Cambio: \$${sale.change.toStringAsFixed(2)} MXN',
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
            const SizedBox(height: 12),
            const Text('El ticket ha sido enviado a la impresora "BlueTooth Printer" de 80mm con autocorte.'),
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
      height: MediaQuery.of(context).size.height * 0.85,
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

          // Selector de Método de Pago
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
                  icon: Icon(Icons.payments_outlined),
                  text: 'Efectivo',
                ),
                Tab(
                  icon: Icon(Icons.qr_code_2),
                  text: 'CoDi (Banxico)',
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

  // --- Vista de Cobro CoDi (Pey) ---
  Widget _buildCodiTab() {
    if (_isLoadingCodi) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Generando código CoDi con Pey Banxico...'),
          ],
        ),
      );
    }

    return Column(
      children: [
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
            onPressed: !_isProcessing ? () => _completeSale('CODI') : null,
          ),
        ),
      ],
    );
  }
}
