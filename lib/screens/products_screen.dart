import 'package:flutter/material.dart';
import '../models/product.dart';
import '../database/db_helper.dart';
import '../services/audio_service.dart';
import 'scanner_sheet.dart';
import '../config/theme.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _products = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final prods = await DbHelper.instance.getProducts(query: _searchQuery);
    if (mounted) {
      setState(() {
        _products = prods;
        _isLoading = false;
      });
    }
  }

  void _openProductForm([Product? product]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProductFormSheet(
        product: product,
        onSaved: () => _loadProducts(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo de Productos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppTheme.primary, size: 28),
            tooltip: 'Nuevo Producto',
            onPressed: () => _openProductForm(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o código de barras...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                filled: true,
              ),
              onChanged: (val) {
                _searchQuery = val;
                _loadProducts();
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(child: Text('No hay productos en el catálogo'))
                    : ListView.separated(
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final prod = _products[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withOpacity(0.15),
                              child: Text(
                                prod.name.isNotEmpty ? prod.name[0].toUpperCase() : 'P',
                                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(prod.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${prod.category} • Stock: ${prod.stock} ${prod.unit}'),
                                if (prod.barcode != null && prod.barcode!.isNotEmpty)
                                  Row(
                                    children: [
                                      const Icon(Icons.qr_code, size: 14, color: AppTheme.secondary),
                                      const SizedBox(width: 4),
                                      Text(prod.barcode!, style: const TextStyle(fontSize: 12, color: AppTheme.secondary)),
                                    ],
                                  )
                                else
                                  const Text('Sin código de barras', style: TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            trailing: Text(
                              '\$${prod.price.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primary,
                              ),
                            ),
                            onTap: () => _openProductForm(prod),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nuevo Producto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () => _openProductForm(),
      ),
    );
  }
}

class _ProductFormSheet extends StatefulWidget {
  final Product? product;
  final VoidCallback onSaved;

  const _ProductFormSheet({this.product, required this.onSaved});

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _barcodeController;
  late TextEditingController _stockController;
  String _category = 'Bebidas';

  final List<String> _categoryOptions = [
    'Bebidas',
    'Botanas',
    'Abarrotes',
    'Antojitos',
    'Lácteos',
    'Frutas y Verduras',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _priceController = TextEditingController(text: p != null ? p.price.toStringAsFixed(2) : '');
    _barcodeController = TextEditingController(text: p?.barcode ?? '');
    _stockController = TextEditingController(text: p != null ? p.stock.toString() : '100');
    if (p != null && _categoryOptions.contains(p.category)) {
      _category = p.category;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _scanBarcode() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ScannerSheet(
        onProductScanned: (prod) {
          if (prod.barcode != null) {
            setState(() {
              _barcodeController.text = prod.barcode!;
            });
          }
          Navigator.pop(ctx);
        },
        onUnknownBarcode: (code) {
          setState(() {
            _barcodeController.text = code;
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final price = double.parse(_priceController.text.trim());
    final barcode = _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim();
    final stock = int.tryParse(_stockController.text.trim()) ?? 100;

    if (widget.product == null) {
      // Nuevo
      final newProd = Product(
        name: name,
        price: price,
        barcode: barcode,
        category: _category,
        stock: stock,
      );
      await DbHelper.instance.insertProduct(newProd);
    } else {
      // Actualizar
      final updated = widget.product!.copyWith(
        name: name,
        price: price,
        barcode: barcode,
        category: _category,
        stock: stock,
      );
      await DbHelper.instance.updateProduct(updated);
    }

    AudioService.playSuccessBeep();
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  void _delete() async {
    if (widget.product?.id == null) return;
    await DbHelper.instance.deleteProduct(widget.product!.id!);
    widget.onSaved();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.product == null ? 'Nuevo Producto' : 'Editar Producto',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  if (widget.product != null)
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent),
                      onPressed: _delete,
                    ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),

              // Nombre
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre del Producto *',
                  hintText: 'Ej. Coca Cola 600ml o Torta de Milanesa',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 16),

              // Precio
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Precio de Venta (\$ MXN) *',
                  hintText: 'Ej. 18.00',
                  prefixText: '\$ ',
                  border: OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) return 'Ingresa el precio';
                  if (double.tryParse(val.trim()) == null) return 'Precio no válido';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Código de barras (OPCIONAL con botón de escanear)
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      decoration: const InputDecoration(
                        labelText: 'Código de barras (Opcional)',
                        hintText: 'Ej. 7501055301072',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: AppTheme.secondary),
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                    tooltip: 'Escanear con cámara',
                    onPressed: _scanBarcode,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Categoría
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
                items: _categoryOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _category = val);
                },
              ),
              const SizedBox(height: 16),

              // Stock
              TextFormField(
                controller: _stockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Existencias (Inventario)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(widget.product == null ? 'Guardar Producto' : 'Actualizar Producto'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
