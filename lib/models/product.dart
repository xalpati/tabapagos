class Product {
  final int? id;
  final String name;
  final double price;
  final String? barcode;
  final String category;
  final int stock;
  final String unit;
  final int colorHex;
  final bool isActive;

  Product({
    this.id,
    required this.name,
    required this.price,
    this.barcode,
    required this.category,
    this.stock = 100,
    this.unit = 'pza',
    this.colorHex = 0xFF059669,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'barcode': barcode?.trim().isEmpty == true ? null : barcode?.trim(),
      'category': category,
      'stock': stock,
      'unit': unit,
      'color_hex': colorHex,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as int?,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      barcode: map['barcode'] as String?,
      category: map['category'] as String? ?? 'General',
      stock: map['stock'] as int? ?? 0,
      unit: map['unit'] as String? ?? 'pza',
      colorHex: map['color_hex'] as int? ?? 0xFF059669,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Product copyWith({
    int? id,
    String? name,
    double? price,
    String? barcode,
    String? category,
    int? stock,
    String? unit,
    int? colorHex,
    bool? isActive,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      barcode: barcode ?? this.barcode,
      category: category ?? this.category,
      stock: stock ?? this.stock,
      unit: unit ?? this.unit,
      colorHex: colorHex ?? this.colorHex,
      isActive: isActive ?? this.isActive,
    );
  }
}
