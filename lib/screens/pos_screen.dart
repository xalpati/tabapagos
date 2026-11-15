import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../database/db_helper.dart';
import '../services/printer_service.dart';
import '../services/audio_service.dart';
import 'scanner_sheet.dart';
import 'payment_modal.dart';
import 'products_screen.dart';
import 'sales_history_screen.dart';
import 'printer_settings_screen.dart';
import 'settings_screen.dart';
import '../config/theme.dart';

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

  // Carrito / Ticket de venta actual
  final List<SaleItem> _cartItems = [];

  // Estado de impresora
  bool _isPrinterConnected = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initPrinter();
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

  Future<void> _initPrinter() async {
    final connected = await PrinterService.instance.autoConnect();
    if (mounted) {
      setState(() {
        _isPrinterConnected = connected;
      });
    }
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

  void _openPaymentModal() {
    if (_cartItems.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PaymentModal(
        total: _cartTotal,
        items: List.from(_cartItems),
        onPaymentCompleted: () {
          _clearCart();
          _loadData();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
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
            const SizedBox(width: 6),
            const Text('Tabapagos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade700.withOpacity(0.18),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.amber.shade700, width: 1),
              ),
              child: Text(
                'DEMO',
                style: TextStyle(
                  color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        actions: [
          // Estado de impresora Bluetooth
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.print,
              color: _isPrinterConnected ? AppTheme.primaryLight : Colors.grey,
            ),
            tooltip: _isPrinterConnected ? 'Impresora 80mm Conectada' : 'Impresora Desconectada',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
              );
              _initPrinter();
            },
          ),
          // Botón Historial de Ventas
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Historial de Ventas',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SalesHistoryScreen()),
              );
            },
          ),
          // Botón Catálogo de Productos
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.inventory_2_outlined),
            tooltip: 'Administrar Catálogo',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProductsScreen()),
              );
              _loadData();
            },
          ),
          // Menú Configuración
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda rápida y botón de escáner cámara
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o código...',
                      prefixIcon: const Icon(Icons.search, size: 22),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                const SizedBox(width: 10),
                // Botón Escáner Cámara Táctil Grande
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.qr_code_scanner, size: 24),
                  label: const Text('Escanear', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _openScanner,
                ),
              ],
            ),
          ),

          // Selector horizontal de Categorías
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = cat == _selectedCategory;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: AppTheme.primary.withOpacity(0.2),
                    checkmarkColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primary : null,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

          const SizedBox(height: 6),

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
                          childAspectRatio: 1.25,
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

          // Barra / Bandeja de Ticket de Venta Inferior
          _buildCartBottomBar(),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        AudioService.playScanBeep();
        _addToCart(product);
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    product.category,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (product.barcode != null && product.barcode!.isNotEmpty)
                  const Icon(Icons.qr_code, size: 14, color: AppTheme.secondary),
              ],
            ),
            Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.primary,
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add, color: AppTheme.primary, size: 20),
                ),
              ],
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
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _cartItems.isNotEmpty ? AppTheme.primary : Colors.grey,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      icon: const Icon(Icons.point_of_sale, size: 22),
                      label: Text(
                        _cartItems.isNotEmpty ? 'Cobrar (\$${_cartTotal.toStringAsFixed(2)})' : 'Cobrar',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _cartItems.isNotEmpty ? _openPaymentModal : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
