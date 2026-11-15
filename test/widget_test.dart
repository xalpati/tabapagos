import 'package:flutter_test/flutter_test.dart';
import 'package:tabapagos/models/product.dart';
import 'package:tabapagos/models/sale_item.dart';

void main() {
  test('Product model serialization and deserialization', () {
    final product = Product(
      id: 1,
      name: 'Coca-Cola 600ml',
      price: 18.0,
      barcode: '7501055301072',
      category: 'Bebidas',
    );

    final map = product.toMap();
    expect(map['name'], 'Coca-Cola 600ml');
    expect(map['price'], 18.0);
    expect(map['barcode'], '7501055301072');

    final reconstructed = Product.fromMap(map);
    expect(reconstructed.name, product.name);
    expect(reconstructed.price, product.price);
    expect(reconstructed.barcode, product.barcode);
  });

  test('SaleItem subtotal calculation', () {
    final item = SaleItem(
      productName: 'Tacos de Canasta',
      price: 36.0,
      quantity: 3,
    );

    expect(item.subtotal, 108.0);
  });
}
