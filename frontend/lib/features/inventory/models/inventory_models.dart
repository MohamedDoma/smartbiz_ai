// SmartBiz AI — Inventory data models.

/// Stock health status.
enum StockStatus { inStock, lowStock, outOfStock }

/// Movement type.
enum MovementType { sale, purchase, adjustment, returnGoods, transfer }

/// Warehouse / location.
class Warehouse {
  final String id;
  final String name;
  final String? address;
  const Warehouse({required this.id, required this.name, this.address});
}

/// Inventory item (per product).
class InventoryItem {
  final String productId;
  final String productName;
  final String? sku;
  int stockQty;
  int reservedQty;
  int lowStockThreshold;
  String warehouseId;
  DateTime lastUpdated;

  InventoryItem({
    required this.productId,
    required this.productName,
    this.sku,
    required this.stockQty,
    this.reservedQty = 0,
    this.lowStockThreshold = 5,
    this.warehouseId = 'wh1',
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  int get availableQty => stockQty - reservedQty;

  StockStatus get status {
    if (stockQty <= 0) return StockStatus.outOfStock;
    if (stockQty <= lowStockThreshold) return StockStatus.lowStock;
    return StockStatus.inStock;
  }
}

/// Stock movement record.
class StockMovement {
  final String id;
  final String productId;
  final String productName;
  final MovementType type;
  final int quantity; // positive = in, negative = out
  final int beforeQty;
  final int afterQty;
  final DateTime timestamp;
  final String? employeeName;
  final String? notes;
  final String? warehouseId;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.beforeQty,
    required this.afterQty,
    required this.timestamp,
    this.employeeName,
    this.notes,
    this.warehouseId,
  });
}
