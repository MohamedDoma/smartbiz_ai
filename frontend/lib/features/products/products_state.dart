// SmartBiz AI — Products state management.
// Performance: lazy mock data + cached filtered list.
import 'package:flutter/material.dart';
import 'models/product_models.dart';
import 'data/mock_products.dart';

class ProductsState extends ChangeNotifier {
  List<Product>? _products;
  String _search = '';
  StockLevel? _stockFilter;
  int _counter = 11;

  List<Product>? _filteredCache;
  int? _lowStockCache;

  List<Product> get _data => _products ??= MockProducts.products();

  // ── Getters ─────────────────────────────────────────────
  List<Product> get all => List.unmodifiable(_data);

  List<Product> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _data.where((p) {
      if (_stockFilter != null && p.stockLevel != _stockFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!p.name.toLowerCase().contains(q) && !p.sku.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _filteredCache!;
  }

  int get lowStockCount {
    _lowStockCache ??= _data.where((p) => p.stockLevel != StockLevel.normal && p.status == ProductStatus.active).length;
    return _lowStockCache!;
  }

  StockLevel? get stockFilter => _stockFilter;
  String get search => _search;

  Product? getById(String id) {
    try { return _data.firstWhere((p) => p.id == id); }
    catch (_) { return null; }
  }

  // ── Actions ─────────────────────────────────────────────
  void _invalidate() { _filteredCache = null; _lowStockCache = null; notifyListeners(); }

  void setSearch(String q) { _search = q; _filteredCache = null; notifyListeners(); }
  void setStockFilter(StockLevel? s) {
    _stockFilter = _stockFilter == s ? null : s;
    _filteredCache = null;
    notifyListeners();
  }

  void createProduct({
    required String name,
    String sku = '',
    required double sellingPrice,
    double costPrice = 0,
    int stock = 0,
    int lowStockThreshold = 5,
  }) {
    _data.add(Product(
      id: 'p${_counter++}',
      name: name,
      sku: sku,
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      stock: stock,
      lowStockThreshold: lowStockThreshold,
    ));
    _invalidate();
  }

  void updateStock(String id, int delta) {
    final p = getById(id);
    if (p != null) {
      p.stock = (p.stock + delta).clamp(0, 999999);
      _invalidate();
    }
  }

  void toggleStatus(String id) {
    final p = getById(id);
    if (p != null) {
      p.status = p.status == ProductStatus.active ? ProductStatus.inactive : ProductStatus.active;
      _invalidate();
    }
  }
}
