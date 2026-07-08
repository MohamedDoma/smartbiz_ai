// SmartBiz AI — Products state management (real API).
//
// Replaces mock data with real backend CRUD via ProductService.
// Keeps existing UI contract: filtered, all, search, stockFilter, lowStockCount.

import 'package:flutter/material.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/product_models.dart';
import '../../core/api/product_service.dart';
import 'models/product_models.dart';

class ProductsState extends ChangeNotifier {
  final ProductService _service;

  ProductsState(this._service);

  // ── Core state ──────────────────────────────────────────
  List<Product> _products = [];
  bool _loading = false;
  bool _hasMore = false;
  int _currentPage = 1;
  String? _error;
  String _search = '';
  StockLevel? _stockFilter;

  // ── Cached filtered view ────────────────────────────────
  List<Product>? _filteredCache;
  int? _lowStockCache;

  // ── Getters ─────────────────────────────────────────────
  List<Product> get all => List.unmodifiable(_products);
  bool get loading => _loading;
  String? get error => _error;
  bool get hasMore => _hasMore;
  StockLevel? get stockFilter => _stockFilter;
  String get search => _search;

  List<Product> get filtered {
    if (_filteredCache != null) return _filteredCache!;
    _filteredCache = _products.where((p) {
      if (_stockFilter != null && p.stockLevel != _stockFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!p.name.toLowerCase().contains(q) &&
            !p.sku.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _filteredCache!;
  }

  int get lowStockCount {
    _lowStockCache ??= _products
        .where((p) =>
            p.stockLevel != StockLevel.normal &&
            p.status == ProductStatus.active)
        .length;
    return _lowStockCache!;
  }

  Product? getById(String id) {
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── Invalidation ────────────────────────────────────────
  void _invalidate() {
    _filteredCache = null;
    _lowStockCache = null;
    notifyListeners();
  }

  // ── Search / Filter ─────────────────────────────────────
  void setSearch(String q) {
    _search = q;
    _filteredCache = null;
    notifyListeners();
  }

  void setStockFilter(StockLevel? s) {
    _stockFilter = _stockFilter == s ? null : s;
    _filteredCache = null;
    notifyListeners();
  }

  // ── Load products from backend ──────────────────────────
  Future<void> loadProducts({bool refresh = false}) async {
    if (_loading) return;

    if (refresh) {
      _currentPage = 1;
      _hasMore = false;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.listProducts(
        page: _currentPage,
        perPage: 50,
      );

      if (refresh || _currentPage == 1) {
        _products = result.data.map(_mapApiProduct).toList();
      } else {
        _products.addAll(result.data.map(_mapApiProduct));
      }

      _hasMore = result.hasMore;
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  /// Load next page if available.
  Future<void> loadMore() async {
    if (!_hasMore || _loading) return;
    _currentPage++;
    await loadProducts();
  }

  // ── Create product ─────────────────────────────────────
  Future<void> createProduct({
    required String name,
    String sku = '',
    required double sellingPrice,
    double costPrice = 0,
    int minStockAlert = 0,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final payload = ProductPayload(
        name: name,
        sku: sku.isNotEmpty ? sku : null,
        basePrice: sellingPrice,
        costPrice: costPrice,
        minStockAlert: minStockAlert,
      );
      final created = await _service.createProduct(payload);
      _products.insert(0, _mapApiProduct(created));
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow; // let UI handle
    }
  }

  // ── Update product ─────────────────────────────────────
  Future<void> updateProduct({
    required String id,
    required String name,
    String sku = '',
    required double sellingPrice,
    double costPrice = 0,
    int minStockAlert = 0,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final payload = ProductPayload(
        name: name,
        sku: sku.isNotEmpty ? sku : null,
        basePrice: sellingPrice,
        costPrice: costPrice,
        minStockAlert: minStockAlert,
      );
      final updated = await _service.updateProduct(id, payload);
      final idx = _products.indexWhere((p) => p.id == id);
      if (idx >= 0) _products[idx] = _mapApiProduct(updated);
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Delete product ─────────────────────────────────────
  Future<void> deleteProduct(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _service.deleteProduct(id);
      _products.removeWhere((p) => p.id == id);
      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Map backend model to UI model ──────────────────────
  static Product _mapApiProduct(ApiProduct api) => Product(
        id: api.id,
        name: api.name,
        sku: api.sku,
        sellingPrice: api.basePrice,
        costPrice: api.costPrice,
        stock: 0, // stock comes from inventory, not product table
        lowStockThreshold: api.minStockAlert,
      );

  // ── Error formatting ───────────────────────────────────
  String _friendlyError(dynamic e) {
    if (e is ValidationException) {
      final msgs = e.errors.values.expand((v) => v).toList();
      return msgs.isNotEmpty ? msgs.first : e.message;
    }
    if (e is AuthException) return 'Session expired. Please login again.';
    if (e is NetworkException) return 'Network error. Check your connection.';
    if (e is ApiException) return e.message;
    return 'Something went wrong.';
  }
}
