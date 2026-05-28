// SmartBiz AI — Inventory state management.
import 'package:flutter/material.dart';
import 'models/inventory_models.dart';
import 'data/mock_inventory.dart';

class InventoryState extends ChangeNotifier {
  final List<InventoryItem> _items = List.from(mockInventory);
  final List<StockMovement> _movements = List.from(mockMovements);
  final List<Warehouse> warehouses = List.from(mockWarehouses);

  String _search = '';
  StockStatus? _statusFilter;
  String? _warehouseFilter;

  // ── Getters ─────────────────────────────────────────────
  List<InventoryItem> get items {
    var list = List<InventoryItem>.from(_items);
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((i) => i.productName.toLowerCase().contains(q) || (i.sku?.toLowerCase().contains(q) ?? false)).toList();
    }
    if (_statusFilter != null) list = list.where((i) => i.status == _statusFilter).toList();
    if (_warehouseFilter != null) list = list.where((i) => i.warehouseId == _warehouseFilter).toList();
    return list;
  }

  List<StockMovement> get movements => List.from(_movements)..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  String get search => _search;
  StockStatus? get statusFilter => _statusFilter;
  String? get warehouseFilter => _warehouseFilter;

  int get totalProducts => _items.length;
  int get lowStockCount => _items.where((i) => i.status == StockStatus.lowStock).length;
  int get outOfStockCount => _items.where((i) => i.status == StockStatus.outOfStock).length;
  int get totalUnits => _items.fold(0, (s, i) => s + i.stockQty);
  List<InventoryItem> get lowStockItems => _items.where((i) => i.status == StockStatus.lowStock).toList();
  List<InventoryItem> get outOfStockItems => _items.where((i) => i.status == StockStatus.outOfStock).toList();

  InventoryItem? getByProductId(String id) {
    try { return _items.firstWhere((i) => i.productId == id); } catch (_) { return null; }
  }

  List<StockMovement> movementsFor(String productId) => _movements.where((m) => m.productId == productId).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  String warehouseName(String id) {
    try { return warehouses.firstWhere((w) => w.id == id).name; } catch (_) { return id; }
  }

  // ── Actions ─────────────────────────────────────────────
  void setSearch(String v) { _search = v; notifyListeners(); }
  void setStatusFilter(StockStatus? v) { _statusFilter = v; notifyListeners(); }
  void setWarehouseFilter(String? v) { _warehouseFilter = v; notifyListeners(); }

  void adjustStock({required String productId, required int delta, required String reason, String? notes}) {
    final item = getByProductId(productId);
    if (item == null) return;
    final before = item.stockQty;
    item.stockQty = (item.stockQty + delta).clamp(0, 999999);
    item.lastUpdated = DateTime.now();
    _movements.insert(0, StockMovement(
      id: 'mv${DateTime.now().millisecondsSinceEpoch}',
      productId: productId, productName: item.productName,
      type: MovementType.adjustment, quantity: delta,
      beforeQty: before, afterQty: item.stockQty,
      timestamp: DateTime.now(), notes: notes ?? reason,
    ));
    notifyListeners();
  }
}
