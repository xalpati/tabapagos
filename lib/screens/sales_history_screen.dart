import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../database/db_helper.dart';
import '../services/printer_service.dart';
import '../config/theme.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Sale> _sales = [];
  Map<String, double> _summary = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    setState(() => _isLoading = true);
    final salesList = await DbHelper.instance.getSales();
    final summaryData = await DbHelper.instance.getTodaySalesSummary();

    if (mounted) {
      setState(() {
        _sales = salesList;
        _summary = summaryData;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial y Corte de Caja'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Resumen del día
                Container(
                  margin: const EdgeInsets.all(14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Ventas de Hoy',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '${_summary['total_sales']?.toInt() ?? 0} ventas',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildSummaryItem('Total Vendido', '\$${(_summary['total_amount'] ?? 0.0).toStringAsFixed(2)}', AppTheme.primary),
                          _buildSummaryItem('Efectivo', '\$${(_summary['cash_amount'] ?? 0.0).toStringAsFixed(2)}', Colors.blue.shade700),
                          _buildSummaryItem('CoDi (Banxico)', '\$${(_summary['codi_amount'] ?? 0.0).toStringAsFixed(2)}', Colors.amber.shade800),
                        ],
                      ),
                    ],
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Últimas Ventas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),

                Expanded(
                  child: _sales.isEmpty
                      ? const Center(child: Text('Aún no se han registrado ventas hoy'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _sales.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final sale = _sales[index];
                            final date = DateTime.tryParse(sale.createdAt);
                            final formattedDate = date != null ? DateFormat('HH:mm - dd/MM').format(date) : sale.createdAt;

                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: sale.paymentMethod == 'CODI'
                                      ? Colors.amber.withOpacity(0.2)
                                      : AppTheme.primary.withOpacity(0.2),
                                  child: Icon(
                                    sale.paymentMethod == 'CODI' ? Icons.qr_code_2 : Icons.payments_outlined,
                                    color: sale.paymentMethod == 'CODI' ? Colors.amber.shade900 : AppTheme.primary,
                                  ),
                                ),
                                title: Text('${sale.folio} • \$${sale.total.toStringAsFixed(2)} MXN', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${sale.items.length} artículos • $formattedDate (${sale.paymentMethod})'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.print, color: AppTheme.primary),
                                  tooltip: 'Reimprimir ticket (80mm)',
                                  onPressed: () async {
                                    final ok = await PrinterService.instance.printSaleTicket(sale);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(ok ? 'Ticket enviado a la impresora' : 'No se pudo conectar a la impresora')),
                                      );
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }
}
