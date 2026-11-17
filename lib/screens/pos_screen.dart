import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../config/theme.dart';
import '../database/db_helper.dart';
import '../services/audio_service.dart';
import 'scanner_sheet.dart';
import 'payment_modal.dart';
import 'products_screen.dart';
import 'sales_history_screen.dart';
import 'printer_settings_screen.dart';
import 'bank_account_screen.dart';
import 'login_screen.dart';
import 'settings_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<Product> _products = [];
  List<String> _categories = ['Todos'];
  String _selectedCategory = 'Todos';
  String _searchQuery = '';
  bool _isLoading = true;

  // Vista activa: 0 = Catálogo, 1 = Cobro Directo (Teclado)
  int _posTab = 0;
  String _directAmountStr = '0';
  final TextEditingController _directConceptController = TextEditingController(text: 'Venta Directa');

  // Carrito / Ticket de venta actual
  final List<SaleItem> _cartItems = [];

  // Estado del sistema y periféricos
  bool _isDemoMode = true;
  bool _isPrinterConnected = false;
  String? _savedPrinterName;
  Map<String, String>? _bankAccount;
  String _businessName = 'Abarrotes & Antojitos Los Primos';

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSettingsAndPeripherals();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final prods = await DbHelper.instance.getProducts(
      query: _searchQuery,
      category: _selectedCategory,
    );
    final cats = await DbHelper.instance.getCategories();

    if (mounted) {
      setState(() {
        _products = prods;
        _categories = ['Todos', ...cats];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSettingsAndPeripherals() async {
    final isDemo = await DbHelper.instance.isDemoMode();
    final printer = await DbHelper.instance.getSavedPrinter();
    final isPrinterConn = await PrintBluetoothThermal.connectionStatus;
    final bank = await DbHelper.instance.getBankAccount();
    final business = await DbHelper.instance.getSetting('business_name', defaultValue: 'Abarrotes & Antojitos Los Primos');

    if (mounted) {
      setState(() {
        _isDemoMode = isDemo;
        _savedPrinterName = printer?['name'];
        _isPrinterConnected = isPrinterConn;
        _bankAccount = bank;
        _businessName = business ?? 'Abarrotes & Antojitos Los Primos';
      });
    }
  }

  Future<void> _exitToLogin() async {
    Navigator.pop(context); // Cerrar Drawer
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isDemoMode ? 'Salir de Modo Demo' : 'Cerrar Sesión'),
        content: Text(
          _isDemoMode
              ? '¿Deseas salir del Modo Demo e ir a la pantalla de inicio de sesión con Google?'
              : '¿Deseas cerrar tu sesión actual?',
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isDemoMode ? Colors.orange : Colors.red,
            ),
            child: Text(
              _isDemoMode ? 'Salir a Login' : 'Cerrar Sesión',
              style: const TextStyle(color: Colors.white),
            ),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await DbHelper.instance.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  // --- Lógica de Cobro Directo (Teclado Rápido) ---

  void _onDirectKeypadTap(String key) {
    setState(() {
      if (key == 'C') {
        _directAmountStr = '0';
      } else if (key == '⌫') {
        if (_directAmountStr.length > 1) {
          _directAmountStr = _directAmountStr.substring(0, _directAmountStr.length - 1);
        } else {
          _directAmountStr = '0';
        }
      } else if (key == '.') {
        if (!_directAmountStr.contains('.')) {
          _directAmountStr += '.';
        }
      } else if (key == '00') {
        if (_directAmountStr != '0') {
          _directAmountStr += '00';
        }
      } else {
        if (_directAmountStr == '0') {
          _directAmountStr = key;
        } else {
          if (_directAmountStr.contains('.')) {
            final parts = _directAmountStr.split('.');
            if (parts.length > 1 && parts[1].length >= 2) return;
          }
          _directAmountStr += key;
        }
      }
    });
  }

  void _addQuickAmount(double addition) {
    final current = double.tryParse(_directAmountStr) ?? 0.0;
    setState(() {
      _directAmountStr = (current + addition).toStringAsFixed(2);
      if (_directAmountStr.endsWith('.00')) {
        _directAmountStr = _directAmountStr.substring(0, _directAmountStr.length - 3);
      }
    });
  }

  void _addDirectAmountToCart() {
    final amount = double.tryParse(_directAmountStr) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto mayor a cero.')),
      );
      return;
    }
    final concept = _directConceptController.text.trim().isEmpty ? 'Venta Directa' : _directConceptController.text.trim();
    final item = SaleItem(
      productName: concept,
      price: amount,
      quantity: 1,
    );
    setState(() {
      final existingIndex = _cartItems.indexWhere((i) => i.productName == concept && i.price == amount);
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity++;
      } else {
        _cartItems.add(item);
      }
      _directAmountStr = '0';
    });
    AudioService.playBeep();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.primary,
        content: Text('+\$${amount.toStringAsFixed(2)} agregado al ticket'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _directImmediateCheckout({int initialTab = 0}) {
    final amount = double.tryParse(_directAmountStr) ?? 0.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto mayor a cero para cobrar.')),
      );
      return;
    }
    final concept = _directConceptController.text.trim().isEmpty ? 'Cobro Directo' : _directConceptController.text.trim();
    final item = SaleItem(
      productName: concept,
      price: amount,
      quantity: 1,
    );
    setState(() {
      _cartItems.add(item);
      _directAmountStr = '0';
    });
    _openPaymentModal(initialTab: initialTab);
  }

  void _addToCart(Product product) {
    setState(() {
      final existingIndex = _cartItems.indexWhere((i) => i.productId == product.id);
      if (existingIndex >= 0) {
        _cartItems[existingIndex].quantity++;
      } else {
        _cartItems.add(SaleItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: 1,
        ));
      }
    });
  }

  void _decreaseQuantity(int index) {
    setState(() {
      if (_cartItems[index].quantity > 1) {
        _cartItems[index].quantity--;
      } else {
        _cartItems.removeAt(index);
      }
    });
  }

  void _increaseQuantity(int index) {
    setState(() {
      _cartItems[index].quantity++;
    });
  }

  void _clearCart() {
    setState(() {
      _cartItems.clear();
    });
  }

  double get _cartTotal => _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);
  int get _cartItemCount => _cartItems.fold(0, (sum, item) => sum + item.quantity);

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScannerSheet(
        onProductScanned: (product) {
          _addToCart(product);
        },
        onUnknownBarcode: (barcode) {
          _showQuickAddDialog(barcode);
        },
      ),
    );
  }

  void _showQuickAddDialog(String barcode) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Producto no registrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Código: $barcode', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre del producto', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Precio \$ MXN', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Cancelar'),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            child: const Text('Guardar y Sumar'),
            onPressed: () async {
              final name = nameController.text.trim();
              final price = double.tryParse(priceController.text) ?? 0.0;
              if (name.isNotEmpty && price > 0) {
                final newProd = Product(
                  name: name,
                  price: price,
                  barcode: barcode,
                  category: 'General',
                );
                final id = await DbHelper.instance.insertProduct(newProd);
                _addToCart(newProd.copyWith(id: id));
                _loadData();
                Navigator.pop(ctx);
              }
            },
          ),
        ],
      ),
    );
  }

  void _openPaymentModal({int initialTab = 0}) {
    if (_cartItems.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PaymentModal(
        total: _cartTotal,
        items: List.from(_cartItems),
        initialTab: initialTab,
        onPaymentCompleted: () {
          _clearCart();
          _loadData();
        },
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    switch (cat.toLowerCase()) {
      case 'bebidas':
        return Icons.local_drink;
      case 'antojitos':
        return Icons.restaurant;
      case 'abarrotes':
        return Icons.shopping_basket;
      case 'botanas':
        return Icons.lunch_dining;
      default:
        return Icons.category;
    }
  }

  Color _getCategoryColor(String cat) {
    switch (cat.toLowerCase()) {
      case 'bebidas':
        return const Color(0xFF0284C7); // Azul
      case 'antojitos':
        return const Color(0xFFD97706); // Naranja
      case 'abarrotes':
        return const Color(0xFF059669); // Verde
      case 'botanas':
        return const Color(0xFFEA580C); // Naranja rojizo
      default:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'POS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Tabapagos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (_isDemoMode) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.amber.shade700,
                    width: 1.2,
                  ),
                ),
                child: Text(
                  'MODO DEMO',
                  style: TextStyle(
                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Botón Historial de Ventas (Único icono en el encabezado según requerimiento)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Historial de Ventas y Corte',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Selector de Vista: Catálogo vs Cobro Directo
          _buildViewModeSelector(isDark),

          // Contenido dinámico según pestaña activa
          Expanded(
            child: _posTab == 0
                ? _buildCatalogView(isDark)
                : _buildDirectChargeView(isDark),
          ),

          // Barra / Bandeja de Ticket de Venta Inferior
          _buildCartBottomBar(),
        ],
      ),
    );
  }

  Widget _buildViewModeSelector(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _posTab = 0),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _posTab == 0
                      ? (isDark ? const Color(0xFF334155) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _posTab == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 18,
                      color: _posTab == 0 ? AppTheme.primary : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Catálogo',
                      style: TextStyle(
                        fontWeight: _posTab == 0 ? FontWeight.bold : FontWeight.w500,
                        color: _posTab == 0
                            ? (isDark ? Colors.white : Colors.black87)
                            : Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _posTab = 1),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _posTab == 1
                      ? (isDark ? const Color(0xFF334155) : Colors.white)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _posTab == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 18,
                      color: _posTab == 1 ? Colors.amber.shade800 : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Cobro Directo',
                      style: TextStyle(
                        fontWeight: _posTab == 1 ? FontWeight.bold : FontWeight.w500,
                        color: _posTab == 1
                            ? (isDark ? Colors.white : Colors.black87)
                            : Colors.grey.shade600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogView(bool isDark) {
    return Column(
      children: [
        // Barra de búsqueda rápida y botón de escáner cámara
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o código...',
                    prefixIcon: const Icon(Icons.search, size: 22),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  ),
                  onChanged: (val) {
                    _searchQuery = val;
                    _loadData();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Botón Escáner Cámara Táctil Grande
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.qr_code_scanner, size: 22),
                label: const Text('Escanear', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _openScanner,
              ),
            ],
          ),
        ),

        // Selector horizontal de Categorías con iconos
        SizedBox(
          height: 42,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final cat = _categories[index];
              final isSelected = cat == _selectedCategory;
              final catIcon = _getCategoryIcon(cat);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  avatar: Icon(
                    catIcon,
                    size: 16,
                    color: isSelected ? AppTheme.primary : Colors.grey.shade600,
                  ),
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: AppTheme.primary.withOpacity(0.18),
                  checkmarkColor: AppTheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primary : null,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected ? AppTheme.primary : Colors.grey.shade300,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  onSelected: (val) {
                    setState(() => _selectedCategory = cat);
                    _loadData();
                  },
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 4),

        // Cuadrícula de Productos
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.store_mall_directory_outlined, size: 60, color: Colors.grey),
                          const SizedBox(height: 12),
                          const Text('No hay productos que coincidan', style: TextStyle(fontSize: 16)),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Agregar Producto'),
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const ProductsScreen()),
                              );
                              _loadData();
                            },
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.15,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _products.length,
                      itemBuilder: (context, index) {
                        final prod = _products[index];
                        return _buildProductCard(prod);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildDirectChargeView(bool isDark) {
    final quickConcepts = ['Venta Directa', 'Antojitos', 'Bebidas', 'Servicio', 'Abarrotes', 'Flete'];
    final quickAmounts = [10.0, 20.0, 50.0, 100.0, 200.0, 500.0];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Campo de concepto / nota rápida
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _directConceptController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.edit_note, color: AppTheme.primary),
                    labelText: 'Concepto o Nota (ej. Venta Directa)',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.grey.shade50,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Borrar monto',
                icon: const Icon(Icons.backspace_outlined, size: 20),
                onPressed: () => setState(() => _directAmountStr = '0'),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Chips de conceptos frecuentes
          SizedBox(
            height: 30,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: quickConcepts.length,
              itemBuilder: (context, i) {
                final c = quickConcepts[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(c, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _directConceptController.text = c;
                    },
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Display grande del monto ingresado
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                    : [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFF86EFAC),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Monto a cobrar:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blueGrey),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '\$ ${_directAmountStr.isEmpty ? "0" : _directAmountStr}',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'MXN',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Botones de incremento rápido (+10, +20, +50, +100, +200, +500)
          Row(
            children: quickAmounts.map((amt) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: AppTheme.primary.withOpacity(0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    ),
                    onPressed: () => _addQuickAmount(amt),
                    child: Text(
                      '+${amt.toInt()}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 8),

          // Teclado numérico táctil estilo POS
          _buildKeypad(isDark),

          const SizedBox(height: 10),

          // Botones de acción: Sumar al Ticket vs Cobrar Inmediato
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppTheme.primary, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.add_shopping_cart, size: 20, color: AppTheme.primary),
                  label: const Text(
                    'Sumar al Ticket',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary),
                  ),
                  onPressed: _addDirectAmountToCart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF047857),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  icon: const Icon(Icons.qr_code_2, size: 20),
                  label: const Text(
                    'Cobro CoDi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _directImmediateCheckout(initialTab: 1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypad(bool isDark) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['.', '0', '⌫'],
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade300),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: keys.map((row) {
          return Row(
            children: row.map((key) {
              final isDelete = key == '⌫';
              Color btnColor;
              Color txtColor;
              if (isDelete) {
                btnColor = isDark ? const Color(0xFF3B1D22) : const Color(0xFFFFE4E6);
                txtColor = Colors.redAccent;
              } else if (key == '.') {
                btnColor = isDark ? const Color(0xFF1E293B) : Colors.white;
                txtColor = AppTheme.primary;
              } else {
                btnColor = isDark ? const Color(0xFF1E293B) : Colors.white;
                txtColor = isDark ? Colors.white : Colors.black87;
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Material(
                    color: btnColor,
                    borderRadius: BorderRadius.circular(10),
                    elevation: 0.5,
                    child: InkWell(
                      onTap: () {
                        AudioService.playBeep();
                        _onDirectKeypadTap(key);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        child: Text(
                          key,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: txtColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header con logotipo y datos del negocio
          Container(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.asset(
                          'assets/images/tabapagos_brand_logo.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.point_of_sale, color: AppTheme.primary, size: 30),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tabapagos POS',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Cobro y Punto de Venta',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Text(
                  _businessName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isDemoMode ? Colors.amber.shade800 : AppTheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isDemoMode ? Icons.science : Icons.verified,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isDemoMode ? 'MODO DEMO' : 'CUENTA CONECTADA',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items de Navegación
          ListTile(
            leading: const Icon(Icons.point_of_sale, color: AppTheme.primary),
            title: const Text('Punto de Venta (Caja)', style: TextStyle(fontWeight: FontWeight.bold)),
            selected: true,
            selectedColor: AppTheme.primary,
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined, color: AppTheme.secondary),
            title: const Text('Catálogo de Productos'),
            trailing: Chip(
              label: Text('${_products.length}', style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
            ),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen()));
              _loadData();
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: Color(0xFFD97706)),
            title: const Text('Historial y Corte de Caja'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SalesHistoryScreen()));
            },
          ),
          const Divider(),

          // Sección de Periféricos y Finanzas
          ListTile(
            leading: const Icon(Icons.print, color: Color(0xFF0284C7)),
            title: const Text('Registrar Impresora (80mm)'),
            subtitle: Text(
              _isPrinterConnected
                  ? '🟢 Conectada (${_savedPrinterName ?? "80mm"})'
                  : '🔴 Desconectada • Tocar para vincular',
              style: TextStyle(
                fontSize: 12,
                color: _isPrinterConnected ? AppTheme.primary : Colors.grey.shade600,
                fontWeight: _isPrinterConnected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()));
              _loadSettingsAndPeripherals();
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_balance, color: Color(0xFF059669)),
            title: const Text('Mi Cuenta Bancaria (CoDi)'),
            subtitle: Text(
              _bankAccount != null
                  ? '🟢 ${_bankAccount!['bank_name']}'
                  : '⚠️ Sin registrar • Tocar para dar de alta',
              style: TextStyle(
                fontSize: 12,
                color: _bankAccount != null ? AppTheme.primary : Colors.orange.shade800,
                fontWeight: _bankAccount != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const BankAccountScreen()));
              _loadSettingsAndPeripherals();
            },
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Configuración General'),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              _loadSettingsAndPeripherals();
            },
          ),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: Text(_isDemoMode ? 'Salir de Modo Demo' : 'Cerrar Sesión'),
            subtitle: Text(
              _isDemoMode ? 'Regresar a la pantalla de acceso' : 'Finalizar sesión de cuenta',
              style: const TextStyle(fontSize: 11),
            ),
            onTap: _exitToLogin,
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final catColor = _getCategoryColor(product.category);
    final catIcon = _getCategoryIcon(product.category);

    return InkWell(
      onTap: () {
        AudioService.playScanBeep();
        _addToCart(product);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera decorativa temática de la categoría
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.12),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(catIcon, size: 14, color: catColor),
                      const SizedBox(width: 4),
                      Text(
                        product.category,
                        style: TextStyle(fontSize: 11, color: catColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (product.barcode != null && product.barcode!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.qr_code, size: 12, color: Colors.blueGrey),
                    ),
                ],
              ),
            ),

            // Nombre y detalles del producto
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${product.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                          ),
                        ),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primary.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartBottomBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Vista de artículos del ticket si hay elementos
            if (_cartItems.isNotEmpty) ...[
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _cartItems.length,
                  itemBuilder: (context, index) {
                    final item = _cartItems[index];
                    return Container(
                      width: 170,
                      margin: const EdgeInsets.only(right: 8, bottom: 4),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            item.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '\$${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: () => _decreaseQuantity(index),
                                    child: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.redAccent),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    child: Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  InkWell(
                                    onTap: () => _increaseQuantity(index),
                                    child: const Icon(Icons.add_circle_outline, size: 20, color: AppTheme.primary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 12),
            ],

            // Fila de Total y Botón de Cobro
            Row(
              children: [
                if (_cartItems.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: 'Vaciar ticket',
                    onPressed: _clearCart,
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_cartItemCount ${_cartItemCount == 1 ? "artículo" : "artículos"}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    Text(
                      '\$${_cartTotal.toStringAsFixed(2)} MXN',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppTheme.primary),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: _cartItems.isNotEmpty ? AppTheme.primary : Colors.grey.shade400,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: Icon(Icons.payments_outlined, size: 20, color: _cartItems.isNotEmpty ? AppTheme.primary : Colors.grey),
                        label: Text(
                          'Efectivo',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _cartItems.isNotEmpty ? AppTheme.primary : Colors.grey,
                          ),
                        ),
                        onPressed: _cartItems.isNotEmpty ? () => _openPaymentModal(initialTab: 0) : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _cartItems.isNotEmpty ? const Color(0xFF047857) : Colors.grey,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.qr_code_2, size: 22),
                        label: const Text(
                          'Cobro CoDi',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _cartItems.isNotEmpty ? () => _openPaymentModal(initialTab: 1) : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
