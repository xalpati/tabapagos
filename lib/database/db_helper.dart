import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../models/product.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';

class DbHelper {
  static final DbHelper instance = DbHelper._init();
  static Database? _database;

  DbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tabapagos_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Tabla de productos
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        barcode TEXT,
        category TEXT NOT NULL,
        stock INTEGER NOT NULL DEFAULT 100,
        unit TEXT NOT NULL DEFAULT 'pza',
        color_hex INTEGER NOT NULL DEFAULT 4278556265,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Tabla de ventas
    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folio TEXT NOT NULL,
        total REAL NOT NULL,
        payment_method TEXT NOT NULL,
        amount_paid REAL NOT NULL,
        change_amount REAL NOT NULL,
        pey_payment_id TEXT,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'COMPLETED'
      )
    ''');

    // Tabla de renglones de venta
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
      )
    ''');

    // Tabla de perfil y configuración
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Sembrar productos de Modo Demo orientados a micronegocios mexicanos
    await _seedDemoProducts(db);
  }

  Future<void> _seedDemoProducts(Database db) async {
    final demoProducts = [
      // Bebidas
      Product(name: 'Coca-Cola 600ml', price: 18.0, barcode: '7501055301072', category: 'Bebidas', colorHex: 0xFFDC2626),
      Product(name: 'Jarritos Mandarina 600ml', price: 14.0, barcode: '7501021400013', category: 'Bebidas', colorHex: 0xFFEA580C),
      Product(name: 'Boing Mango 500ml', price: 15.0, barcode: '7501031301018', category: 'Bebidas', colorHex: 0xFFF59E0B),
      Product(name: 'Agua de Horchata 1L', price: 25.0, barcode: null, category: 'Bebidas', colorHex: 0xFF0284C7),
      Product(name: 'Café de Olla con Canela', price: 15.0, barcode: null, category: 'Bebidas', colorHex: 0xFF78350F),

      // Botanas y Dulces
      Product(name: 'Sabritas Sal 45g', price: 19.0, barcode: '7501011115453', category: 'Botanas', colorHex: 0xFFEAB308),
      Product(name: 'Doritos Nacho 58g', price: 20.0, barcode: '7501011115651', category: 'Botanas', colorHex: 0xFFEA580C),
      Product(name: 'Gansito Marinela', price: 16.0, barcode: '7501000111206', category: 'Botanas', colorHex: 0xFF2563EB),
      Product(name: 'Paleta Payaso Ricolino', price: 17.0, barcode: '7501000122349', category: 'Botanas', colorHex: 0xFF9333EA),

      // Abarrotes esenciales
      Product(name: 'Huevo Blanco 1 Kg', price: 42.0, barcode: null, category: 'Abarrotes', colorHex: 0xFF10B981),
      Product(name: 'Leche Lala Entera 1L', price: 28.0, barcode: '7501020511116', category: 'Abarrotes', colorHex: 0xFF0284C7),
      Product(name: 'Pan Blanco Bimbo Gde', price: 46.0, barcode: '7501000111800', category: 'Abarrotes', colorHex: 0xFF2563EB),
      Product(name: 'Frijoles Isadora 430g', price: 19.5, barcode: '7501045402017', category: 'Abarrotes', colorHex: 0xFF78350F),

      // Comida / Puesto / Antojitos
      Product(name: 'Tacos de Canasta (4 pzas)', price: 36.0, barcode: null, category: 'Antojitos', colorHex: 0xFF059669),
      Product(name: 'Torta de Milanesa Especial', price: 55.0, barcode: null, category: 'Antojitos', colorHex: 0xFF047857),
      Product(name: 'Quesadilla de Chicharrón', price: 28.0, barcode: null, category: 'Antojitos', colorHex: 0xFFD97706),
      Product(name: 'Tamal Verde o Mole', price: 20.0, barcode: null, category: 'Antojitos', colorHex: 0xFF16A34A),
    ];

    for (var p in demoProducts) {
      await db.insert('products', p.toMap());
    }
  }

  // --- Operaciones de Productos ---

  Future<List<Product>> getProducts({String? query, String? category}) async {
    final db = await instance.database;
    String whereClause = 'is_active = 1';
    List<dynamic> whereArgs = [];

    if (query != null && query.trim().isNotEmpty) {
      whereClause += ' AND (name LIKE ? OR barcode LIKE ?)';
      whereArgs.add('%$query%');
      whereArgs.add('%$query%');
    }

    if (category != null && category != 'Todos') {
      whereClause += ' AND category = ?';
      whereArgs.add(category);
    }

    final result = await db.query(
      'products',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    return result.map((json) => Product.fromMap(json)).toList();
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await instance.database;
    final result = await db.query(
      'products',
      where: 'barcode = ? AND is_active = 1',
      whereArgs: [barcode.trim()],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return Product.fromMap(result.first);
    }
    return null;
  }

  Future<int> insertProduct(Product product) async {
    final db = await instance.database;
    return await db.insert('products', product.toMap());
  }

  Future<int> updateProduct(Product product) async {
    final db = await instance.database;
    return await db.update(
      'products',
      product.toMap(),
      where: 'id = ?',
      whereArgs: [product.id],
    );
  }

  Future<int> deleteProduct(int id) async {
    final db = await instance.database;
    return await db.update(
      'products',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<String>> getCategories() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT DISTINCT category FROM products WHERE is_active = 1 ORDER BY category ASC');
    return result.map((row) => row['category'] as String).toList();
  }

  // --- Operaciones de Ventas ---

  Future<int> insertSale(Sale sale) async {
    final db = await instance.database;
    return await db.transaction((txn) async {
      final saleId = await txn.insert('sales', sale.toMap());
      for (var item in sale.items) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': item.productId,
          'product_name': item.productName,
          'price': item.price,
          'quantity': item.quantity,
          'subtotal': item.subtotal,
        });

        // Descontar inventario si tiene productId
        if (item.productId != null) {
          await txn.rawUpdate(
            'UPDATE products SET stock = stock - ? WHERE id = ?',
            [item.quantity, item.productId],
          );
        }
      }
      return saleId;
    });
  }

  Future<List<Sale>> getSales({int limit = 50}) async {
    final db = await instance.database;
    final saleMaps = await db.query(
      'sales',
      orderBy: 'id DESC',
      limit: limit,
    );

    List<Sale> sales = [];
    for (var sMap in saleMaps) {
      final saleId = sMap['id'] as int;
      final itemMaps = await db.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      final items = itemMaps.map((i) => SaleItem.fromMap(i)).toList();
      sales.add(Sale.fromMap(sMap, items: items));
    }
    return sales;
  }

  Future<Map<String, double>> getTodaySalesSummary() async {
    final db = await instance.database;
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final result = await db.rawQuery('''
      SELECT 
        COUNT(id) as total_sales,
        COALESCE(SUM(total), 0) as total_amount,
        COALESCE(SUM(CASE WHEN payment_method = 'EFECTIVO' THEN total ELSE 0 END), 0) as cash_amount,
        COALESCE(SUM(CASE WHEN payment_method = 'CODI' THEN total ELSE 0 END), 0) as codi_amount
      FROM sales
      WHERE created_at LIKE '$todayStr%' AND status = 'COMPLETED'
    ''');

    if (result.isNotEmpty) {
      return {
        'total_sales': (result.first['total_sales'] as num).toDouble(),
        'total_amount': (result.first['total_amount'] as num).toDouble(),
        'cash_amount': (result.first['cash_amount'] as num).toDouble(),
        'codi_amount': (result.first['codi_amount'] as num).toDouble(),
      };
    }
    return {'total_sales': 0, 'total_amount': 0, 'cash_amount': 0, 'codi_amount': 0};
  }
}
