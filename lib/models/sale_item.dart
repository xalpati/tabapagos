class SaleItem {
  final int? id;
  final int? saleId;
  final int? productId;
  final String productName;
  final double price;
  int quantity;

  SaleItem({
    this.id,
    this.saleId,
    this.productId,
    required this.productName,
    required this.price,
    this.quantity = 1,
  });

  double get subtotal => price * quantity;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sale_id': saleId,
      'product_id': productId,
      'product_name': productName,
      'price': price,
      'quantity': quantity,
      'subtotal': subtotal,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      id: map['id'] as int?,
      saleId: map['sale_id'] as int?,
      productId: map['product_id'] as int?,
      productName: map['product_name'] as String,
      price: (map['price'] as num).toDouble(),
      quantity: map['quantity'] as int? ?? 1,
    );
  }
}
