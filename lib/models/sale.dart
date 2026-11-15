import 'sale_item.dart';

class Sale {
  final int? id;
  final String folio;
  final double total;
  final String paymentMethod; // 'EFECTIVO' | 'CODI'
  final double amountPaid;
  final double change;
  final String? peyPaymentId;
  final String createdAt;
  final String status; // 'COMPLETED' | 'CANCELLED'
  final List<SaleItem> items;

  Sale({
    this.id,
    required this.folio,
    required this.total,
    required this.paymentMethod,
    required this.amountPaid,
    required this.change,
    this.peyPaymentId,
    required this.createdAt,
    this.status = 'COMPLETED',
    this.items = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'folio': folio,
      'total': total,
      'payment_method': paymentMethod,
      'amount_paid': amountPaid,
      'change_amount': change,
      'pey_payment_id': peyPaymentId,
      'created_at': createdAt,
      'status': status,
    };
  }

  factory Sale.fromMap(Map<String, dynamic> map, {List<SaleItem> items = const []}) {
    return Sale(
      id: map['id'] as int?,
      folio: map['folio'] as String,
      total: (map['total'] as num).toDouble(),
      paymentMethod: map['payment_method'] as String,
      amountPaid: (map['amount_paid'] as num).toDouble(),
      change: (map['change_amount'] as num).toDouble(),
      peyPaymentId: map['pey_payment_id'] as String?,
      createdAt: map['created_at'] as String,
      status: map['status'] as String? ?? 'COMPLETED',
      items: items,
    );
  }
}
