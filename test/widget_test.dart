import 'package:flutter_test/flutter_test.dart';
import 'package:tabapagos/models/product.dart';
import 'package:tabapagos/models/sale_item.dart';
import 'package:tabapagos/utils/clabe_validator.dart';

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

  group('ClabeValidator tests', () {
    test('Validates length and checksum correctly', () {
      // CLABE inválida por longitud
      expect(ClabeValidator.validate('0121800001183573'), false);
      expect(ClabeValidator.validate('0121800001183573170'), false);

      // CLABE inválida por caracteres no numéricos
      expect(ClabeValidator.validate('01218000011835731A'), false);

      // CLABE calculada válida
      expect(ClabeValidator.validate('012180000118357317'), true);

      // CLABE con dígito verificador erróneo (cambiamos último dígito de 7 a 8)
      expect(ClabeValidator.validate('012180000118357318'), false);
    });

    test('Detects bank names from code prefix', () {
      expect(ClabeValidator.getBankName('012180000118357317'), 'BBVA México');
      expect(ClabeValidator.getBankName('002180000000000000'), 'Citibanamex');
      expect(ClabeValidator.getBankName('684180000000000000'), 'Nu México');
      expect(ClabeValidator.getBankName('12'), '');
    });
  });
}
