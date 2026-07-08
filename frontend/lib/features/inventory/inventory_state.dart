// SmartBiz AI — Inventory state management (real API).
//
// Replaces mock data with real backend CRUD via WarehouseService + InventoryService.
// Keeps existing UI contract: items, movements, warehouses, summary getters.

import 'package:flutter/material.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/warehouse_models.dart';
import '../../core/api/warehouse_service.dart';
import '../../core/api/inventory_models.dart';
import '../../core/api/inventory_service.dart';
import 'models/inventory_models.dart';

class InventoryState extends ChangeNotifier {
  final WarehouseService _whService;
  final InventoryService _invService;

  InventoryState(this._whService, this._invService);

  // ── Core state ──────────────────────────────────────────
  List<InventoryItem> _items = [];
  List<StockMovement> _movements = [];
  List<Warehouse> _warehouses = [];
  bool _loading = false;
  String? _error;
  String _search = '';
  StockStatus? _statusFilter;
  String? _warehouseFilter;

  // Cached filtered lists
  List<InventoryItem>? _filteredCache;
  List<StockMovement>? _sortedMovementsCache;

  // ── Getters ─────────────────────────────────────────────
  bool get loading => _loading;
  String? get error => _error;
  String get search => _search;
  StockStatus? get statusFilter => _statusFilter;
  String? get warehouseFilter => _warehouseFilter;
  List<Warehouse> get warehouses => _warehouses;

  List<InventoryItem> get items {
    if (_filteredCache != null) return _filteredCache!;
    var list = List<InventoryItem>.from(_items);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((i) =>
              i.productName.toLowerCase().contains(q) ||
              (i.sku?.toLowerCase().contains(q) ?? false))
          .toList();
    }
    if (_statusFilter != null) {
      list = list.where((i) => i.status == _statusFilter).toList();
    }
    if (_warehouseFilter != null) {
      list = list.where((i) => i.warehouseId == _warehouseFilter).toList();
    }
    _filteredCache = list;
    return _filteredCache!;
  }

  List<StockMovement> get movements {
    if (_sortedMovementsCache != null) return _sortedMovementsCache!;
    _sortedMovementsCache = List.from(_movements)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _sortedMovementsCache!;
  }

  int get totalProducts => _items.length;
  int get lowStockCount =>
      _items.where((i) => i.status == StockStatus.lowStock).length;
  int get outOfStockCount =>
      _items.where((i) => i.status == StockStatus.outOfStock).length;
  int get totalUnits => _items.fold(0, (s, i) => s + i.stockQty);

  List<InventoryItem> get lowStockItems =>
      _items.where((i) => i.status == StockStatus.lowStock).toList();
  List<InventoryItem> get outOfStockItems =>
      _items.where((i) => i.status == StockStatus.outOfStock).toList();

  InventoryItem? getByProductId(String id) {
    try {
      return _items.firstWhere((i) => i.productId == id);
    } catch (_) {
      return null;
    }
  }

  List<StockMovement> movementsFor(String productId) => _movements
      .where((m) => m.productId == productId)
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  String warehouseName(String id) {
    try {
      return _warehouses.firstWhere((w) => w.id == id).name;
    } catch (_) {
      return id.length > 8 ? id.substring(0, 8) : id;
    }
  }

  // ── Invalidation ────────────────────────────────────────
  void _invalidate() {
    _filteredCache = null;
    _sortedMovementsCache = null;
    notifyListeners();
  }

  // ── Search / Filter ─────────────────────────────────────
  void setSearch(String v) {
    _search = v;
    _filteredCache = null;
    notifyListeners();
  }

  void setStatusFilter(StockStatus? v) {
    _statusFilter = _statusFilter == v ? null : v;
    _filteredCache = null;
    notifyListeners();
  }

  void setWarehouseFilter(String? v) {
    _warehouseFilter = _warehouseFilter == v ? null : v;
    _filteredCache = null;
    notifyListeners();
  }

  // ── Load all data from backend ──────────────────────────
  Future<void> loadAll({bool refresh = false}) async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Load warehouses, levels, and movements in parallel
      final results = await Future.wait([
        _whService.listWarehouses(),
        _invService.getInventoryLevels(),
        _invService.listMovements(perPage: 50),
      ]);

      final whResult = results[0] as WarehouseListResult;
      final levels = results[1] as List<InventoryLevel>;
      final mvResult = results[2] as InventoryMovementListResult;

      _warehouses = whResult.data
          .map((w) => Warehouse(id: w.id, name: w.name, address: w.location))
          .toList();

      _items = levels.map(_mapLevel).toList();

      _movements = mvResult.data.map(_mapMovement).toList();

      _loading = false;
      _invalidate();
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
    }
  }

  // ── Create warehouse ───────────────────────────────────
  Future<void> createWarehouse(WarehousePayload payload) async {
    try {
      final created = await _whService.createWarehouse(payload);
      _warehouses
          .add(Warehouse(id: created.id, name: created.name, address: created.location));
      notifyListeners();
    } catch (e) {
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Create movement (stock adjustment) ─────────────────
  Future<void> createMovement(InventoryMovementPayload payload) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _invService.createMovement(payload);
      // Reload all data to get updated levels
      _loading = false;
      await loadAll(refresh: true);
    } catch (e) {
      _loading = false;
      _error = _friendlyError(e);
      notifyListeners();
      rethrow;
    }
  }

  // ── Adjust stock (convenience, used by restock dialog) ──
  Future<void> adjustStock({
    required String productId,
    required String warehouseId,
    required int delta,
    required String reason,
    String? notes,
  }) async {
    final type = delta >= 0 ? 'adjustment_increase' : 'adjustment_decrease';
    final payload = InventoryMovementPayload(
      warehouseId: warehouseId,
      productId: productId,
      movementType: type,
      quantityChange: delta.abs().toDouble(),
      reasonCode: reason,
      notes: notes,
    );
    await createMovement(payload);
  }

  // ── Map backend level to UI model ──────────────────────
  static InventoryItem _mapLevel(InventoryLevel level) {
    return InventoryItem(
      productId: level.productId,
      productName: level.productName,
      sku: level.sku,
      stockQty: level.currentStock.round(),
      lowStockThreshold: level.minStockAlert?.round() ?? 5,
      warehouseId: level.warehouseId,
    );
  }

  // ── Map backend movement to UI model ───────────────────
  static StockMovement _mapMovement(ApiInventoryMovement api) {
    final type = _mapMovementType(api.movementType);
    return StockMovement(
      id: api.id,
      productId: api.productId ?? '',
      productName: api.productName ?? 'Unknown',
      type: type,
      quantity: api.quantityChange.round(),
      beforeQty: api.quantityBefore.round(),
      afterQty: api.quantityAfter.round(),
      timestamp: api.createdAt != null
          ? DateTime.tryParse(api.createdAt!) ?? DateTime.now()
          : DateTime.now(),
      notes: api.notes ?? api.reasonCode,
      warehouseId: api.warehouseId,
    );
  }

  static MovementType _mapMovementType(String type) => switch (type) {
        'sale_shipment' => MovementType.sale,
        'purchase_receipt' || 'opening_balance' => MovementType.purchase,
        'return_restock' || 'return_dispose' || 'supplier_return' =>
          MovementType.returnGoods,
        'transfer_in' || 'transfer_out' => MovementType.transfer,
        _ => MovementType.adjustment,
      };

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
