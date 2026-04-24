// SmartBiz AI — Products state management.
import 'package:flutter/material.dart';
import 'models/product_models.dart';
import 'data/mock_products.dart';

class ProductsState extends ChangeNotifier {
  final List<Product> _products = MockProducts.products();
  String _search = '';
  StockLevel? _stockFilter;
  int _counter = 11;

  // ── Getters ─────────────────────────────────────────────
  List<Product> get all => List.unmodifiable(_products);

  List<Product> get filtered {
    return _products.where((p) {
      if (_stockFilter != null && p.stockLevel != _stockFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!p.name.toLowerCase().contains(q) && !p.sku.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<Product> get lowStockProducts => _products.where((p) => p.stockLevel != StockLevel.normal && p.status == ProductStatus.active).toList();
  int get lowStockCount => lowStockProducts.length;

  StockLevel? get stockFilter => _stockFilter;
  String get search => _search;

  Product? getById(String id) {
    try { return _products.firstWhere((p) => p.id == id); }
    catch (_) { return null; }
  }

  // ── Actions ─────────────────────────────────────────────
  void setSearch(String q) { _search = q; notifyListeners(); }
  void setStockFilter(StockLevel? s) {
    _stockFilter = _stockFilter == s ? null : s;
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
    _products.add(Product(
      id: 'p${_counter++}',
      name: name,
      sku: sku,
      sellingPrice: sellingPrice,
      costPrice: costPrice,
      stock: stock,
      lowStockThreshold: lowStockThreshold,
    ));
    notifyListeners();
  }

  void updateStock(String id, int delta) {
    final p = getById(id);
    if (p != null) {
      p.stock = (p.stock + delta).clamp(0, 999999);
      notifyListeners();
    }
  }

  void toggleStatus(String id) {
    final p = getById(id);
    if (p != null) {
      p.status = p.status == ProductStatus.active ? ProductStatus.inactive : ProductStatus.active;
      notifyListeners();
    }
  }
}
