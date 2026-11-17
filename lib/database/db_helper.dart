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

    // Nota: Los productos demo solo se siembran cuando se activa explícitamente el Modo Demo.
    // Para usuarios nuevos o cuentas registradas, el catálogo comienza limpio.
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
        COALESCE(SUM(CASE WHEN payment_method LIKE 'CODI%' THEN total ELSE 0 END), 0) as codi_amount
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

  // --- Operaciones de Configuración y Ajustes Generales ---

  Future<String?> getSetting(String key, {String? defaultValue}) async {
    final db = await instance.database;
    final res = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (res.isNotEmpty) {
      return res.first['value'] as String?;
    }
    return defaultValue;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await instance.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Control de Modo Demo ---

  Future<bool> isDemoMode() async {
    final val = await getSetting('demo_mode', defaultValue: 'true');
    return val == 'true';
  }

  Future<void> setDemoMode(bool enabled) async {
    await setSetting('demo_mode', enabled ? 'true' : 'false');
  }

  Future<void> clearCatalog() async {
    final db = await instance.database;
    await db.delete('products');
  }

  /// Limpia por completo los datos de catálogo, ventas y configuraciones bancarias/impresoras
  /// para que un usuario recién registrado empiece 100% en blanco.
  Future<void> clearAllDataForNewUser() async {
    final db = await instance.database;
    await db.delete('products');
    await db.delete('sale_items');
    await db.delete('sales');
    await db.delete('settings', where: "key LIKE 'bank_%' OR key LIKE 'printer_%' OR key LIKE 'business_%'");
  }

  /// Siembra los productos demo solo si el catálogo está actualmente vacío
  Future<void> seedDemoProductsIfEmpty() async {
    final db = await instance.database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products')) ?? 0;
    if (count == 0) {
      await _seedDemoProducts(db);
    }
  }

  Future<void> restoreDemoCatalog() async {
    final db = await instance.database;
    await db.delete('products');
    await _seedDemoProducts(db);
    await setDemoMode(true);
  }

  // --- Control de Impresora Bluetooth Registrada ---

  Future<Map<String, String>?> getSavedPrinter() async {
    final mac = await getSetting('printer_mac');
    final name = await getSetting('printer_name');
    if (mac != null && mac.isNotEmpty) {
      return {
        'mac': mac,
        'name': name ?? 'BlueTooth Printer',
      };
    }
    return null;
  }

  Future<void> savePrinter(String mac, String name) async {
    await setSetting('printer_mac', mac);
    await setSetting('printer_name', name);
  }

  Future<void> forgetPrinter() async {
    final db = await instance.database;
    await db.delete('settings', where: 'key IN (?, ?)', whereArgs: ['printer_mac', 'printer_name']);
  }

  // --- Control de Cuenta Bancaria Registrada ---

  Future<Map<String, String>?> getBankAccount() async {
    final clabe = await getSetting('bank_clabe');
    if (clabe == null || clabe.isEmpty) return null;

    return {
      'alias': (await getSetting('bank_alias')) ?? 'Cuenta Principal',
      'holder_name': (await getSetting('bank_holder_name')) ?? '',
      'clabe': clabe,
      'entity': (await getSetting('bank_entity')) ?? 'PERSON',
      'status': (await getSetting('bank_status')) ?? 'ACTIVE',
      'bank_name': (await getSetting('bank_name')) ?? 'Banco Nacional',
    };
  }

  Future<void> saveBankAccount({
    required String alias,
    required String holderName,
    required String clabe,
    required String entity,
    required String bankName,
    String status = 'ACTIVE',
  }) async {
    await setSetting('bank_alias', alias);
    await setSetting('bank_holder_name', holderName);
    await setSetting('bank_clabe', clabe);
    await setSetting('bank_entity', entity);
    await setSetting('bank_name', bankName);
    await setSetting('bank_status', status);
  }

  Future<void> deleteBankAccount() async {
    final db = await instance.database;
    await db.delete('settings', where: 'key LIKE ?', whereArgs: ['bank_%']);
  }

  // --- Control de Sesión y Autenticación ---

  Future<bool> hasActiveSession() async {
    final loggedIn = await getSetting('auth_logged_in', defaultValue: '0');
    final isDemo = await getSetting('is_demo_session', defaultValue: '0');
    return loggedIn == '1' || isDemo == '1';
  }

  Future<bool> isGoogleLoggedIn() async {
    final loggedIn = await getSetting('auth_logged_in', defaultValue: '0');
    return loggedIn == '1';
  }

  Future<void> startUserSession({
    required String token,
    required String email,
    required String name,
    required String deviceId,
  }) async {
    await setSetting('auth_logged_in', '1');
    await setSetting('is_demo_session', '0');
    await setSetting('auth_token', token);
    await setSetting('auth_user_email', email);
    await setSetting('auth_user_name', name);
    await setSetting('auth_device_id', deviceId);
    await setDemoMode(false);
  }

  Future<void> startGoogleSession({
    required String token,
    required String email,
    required String name,
    required String deviceId,
  }) async {
    await startUserSession(
      token: token,
      email: email,
      name: name,
      deviceId: deviceId,
    );
  }

  Future<String?> getAuthToken() async {
    return await getSetting('auth_token');
  }

  Future<String?> getUserEmail() async {
    return await getSetting('auth_user_email');
  }

  Future<String?> getUserName() async {
    return await getSetting('auth_user_name');
  }

  Future<bool> isDemoSession() async {
    final isDemo = await getSetting('is_demo_session', defaultValue: '0');
    final email = await getSetting('auth_user_email', defaultValue: '');
    return isDemo == '1' || email == 'demo@tabapagos.com';
  }

  Future<void> startDemoSession() async {
    await setSetting('auth_logged_in', '0');
    await setSetting('is_demo_session', '1');
    await setDemoMode(true);
    await seedDemoProductsIfEmpty();
  }

  Future<void> logout() async {
    await setSetting('auth_logged_in', '0');
    await setSetting('is_demo_session', '0');
    await setSetting('auth_token', '');
  }

  // --- Opciones de Ticket e Impresión ---

  Future<String?> getLogoPath() async {
    final p = await getSetting('business_logo_path');
    if (p != null && p.trim().isNotEmpty) return p.trim();
    return null;
  }

  Future<void> setLogoPath(String? path) async {
    await setSetting('business_logo_path', path ?? '');
  }

  Future<int> getFeedLines() async {
    final v = await getSetting('ticket_feed_lines', defaultValue: '3');
    return int.tryParse(v ?? '3') ?? 3;
  }

  Future<void> setFeedLines(int lines) async {
    await setSetting('ticket_feed_lines', lines.toString());
  }
}
