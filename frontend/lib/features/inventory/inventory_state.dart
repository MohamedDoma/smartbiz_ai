// SmartBiz AI — Inventory state management.
// Performance: lazy mock data + cached filtered/sorted lists.
import 'package:flutter/material.dart';
import 'models/inventory_models.dart';
import 'data/mock_inventory.dart';

class InventoryState extends ChangeNotifier {
  List<InventoryItem>? _items;
  List<StockMovement>? _movements;
  List<Warehouse>? _warehouses;

  String _search = '';
  StockStatus? _statusFilter;
  String? _warehouseFilter;

  List<InventoryItem>? _filteredCache;
  List<StockMovement>? _sortedMovementsCache;

  List<InventoryItem> get _data => _items ??= List.from(mockInventory);
  List<StockMovement> get _mvData => _movements ??= List.from(mockMovements);

  // ── Getters ─────────────────────────────────────────────
  List<Warehouse> get warehouses => _warehouses ??= List.from(mockWarehouses);

  List<InventoryItem> get items {
    if (_filteredCache != null) return _filteredCache!;
    var list = List<InventoryItem>.from(_data);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((i) => i.productName.toLowerCase().contains(q) || (i.sku?.toLowerCase().contains(q) ?? false)).toList();
    }
    if (_statusFilter != null) list = list.where((i) => i.status == _statusFilter).toList();
    if (_warehouseFilter != null) list = list.where((i) => i.warehouseId == _warehouseFilter).toList();
    _filteredCache = list;
    return _filteredCache!;
  }

  List<StockMovement> get movements {
    if (_sortedMovementsCache != null) return _sortedMovementsCache!;
    _sortedMovementsCache = List.from(_mvData)..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return _sortedMovementsCache!;
  }

  String get search => _search;
  StockStatus? get statusFilter => _statusFilter;
  String? get warehouseFilter => _warehouseFilter;

  int get totalProducts => _data.length;
  int get lowStockCount => _data.where((i) => i.status == StockStatus.lowStock).length;
  int get outOfStockCount => _data.where((i) => i.status == StockStatus.outOfStock).length;
  int get totalUnits => _data.fold(0, (s, i) => s + i.stockQty);
  List<InventoryItem> get lowStockItems => _data.where((i) => i.status == StockStatus.lowStock).toList();
  List<InventoryItem> get outOfStockItems => _data.where((i) => i.status == StockStatus.outOfStock).toList();

  InventoryItem? getByProductId(String id) {
    try { return _data.firstWhere((i) => i.productId == id); } catch (_) { return null; }
  }

  List<StockMovement> movementsFor(String productId) => _mvData.where((m) => m.productId == productId).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  String warehouseName(String id) {
    try { return warehouses.firstWhere((w) => w.id == id).name; } catch (_) { return id; }
  }

  // ── Actions ─────────────────────────────────────────────
  void _invalidate() { _filteredCache = null; _sortedMovementsCache = null; notifyListeners(); }

  void setSearch(String v) { _search = v; _filteredCache = null; notifyListeners(); }
  void setStatusFilter(StockStatus? v) { _statusFilter = v; _filteredCache = null; notifyListeners(); }
  void setWarehouseFilter(String? v) { _warehouseFilter = v; _filteredCache = null; notifyListeners(); }

  void adjustStock({required String productId, required int delta, required String reason, String? notes}) {
    final item = getByProductId(productId);
    if (item == null) return;
    final before = item.stockQty;
    item.stockQty = (item.stockQty + delta).clamp(0, 999999);
    item.lastUpdated = DateTime.now();
    _mvData.insert(0, StockMovement(
      id: 'mv${DateTime.now().millisecondsSinceEpoch}',
      productId: productId, productName: item.productName,
      type: MovementType.adjustment, quantity: delta,
      beforeQty: before, afterQty: item.stockQty,
      timestamp: DateTime.now(), notes: notes ?? reason,
    ));
    _invalidate();
  }
}
