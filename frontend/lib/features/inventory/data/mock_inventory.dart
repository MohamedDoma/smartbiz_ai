// SmartBiz AI — Mock inventory data.
import '../models/inventory_models.dart';

final List<Warehouse> mockWarehouses = [
  const Warehouse(id: 'wh1', name: 'Main Warehouse', address: 'Riyadh Industrial Area'),
  const Warehouse(id: 'wh2', name: 'Retail Store', address: 'Riyadh, Olaya St'),
  const Warehouse(id: 'wh3', name: 'Branch A', address: 'Jeddah, Tahlia St'),
];

final List<InventoryItem> mockInventory = [
  InventoryItem(productId: 'p1', productName: 'Premium Widget Pro', sku: 'WDG-001', stockQty: 145, reservedQty: 12, lowStockThreshold: 20, warehouseId: 'wh1', lastUpdated: DateTime.now().subtract(const Duration(hours: 3))),
  InventoryItem(productId: 'p2', productName: 'Smart Sensor X', sku: 'SNS-002', stockQty: 8, lowStockThreshold: 15, warehouseId: 'wh1', lastUpdated: DateTime.now().subtract(const Duration(hours: 8))),
  InventoryItem(productId: 'p3', productName: 'Industrial Cable 5m', sku: 'CBL-003', stockQty: 320, lowStockThreshold: 50, warehouseId: 'wh1', lastUpdated: DateTime.now().subtract(const Duration(days: 1))),
  InventoryItem(productId: 'p4', productName: 'LED Panel 60x60', sku: 'LED-004', stockQty: 3, lowStockThreshold: 10, warehouseId: 'wh2', lastUpdated: DateTime.now().subtract(const Duration(hours: 1))),
  InventoryItem(productId: 'p5', productName: 'Thermal Paste 10g', sku: 'THP-005', stockQty: 0, lowStockThreshold: 5, warehouseId: 'wh2', lastUpdated: DateTime.now().subtract(const Duration(days: 2))),
  InventoryItem(productId: 'p6', productName: 'USB Hub 7-Port', sku: 'USB-006', stockQty: 52, lowStockThreshold: 10, warehouseId: 'wh3', lastUpdated: DateTime.now().subtract(const Duration(days: 1))),
  InventoryItem(productId: 'p7', productName: 'Power Supply 500W', sku: 'PSU-007', stockQty: 4, lowStockThreshold: 8, warehouseId: 'wh1', lastUpdated: DateTime.now().subtract(const Duration(hours: 5))),
  InventoryItem(productId: 'p8', productName: 'Ethernet Switch 8P', sku: 'NET-008', stockQty: 67, lowStockThreshold: 10, warehouseId: 'wh3', lastUpdated: DateTime.now().subtract(const Duration(hours: 12))),
];

final List<StockMovement> mockMovements = [
  StockMovement(id: 'm1', productId: 'p1', productName: 'Premium Widget Pro', type: MovementType.sale, quantity: -5, beforeQty: 150, afterQty: 145, timestamp: DateTime.now().subtract(const Duration(hours: 3)), employeeName: 'Sara M.', notes: 'Invoice #INV-001'),
  StockMovement(id: 'm2', productId: 'p2', productName: 'Smart Sensor X', type: MovementType.sale, quantity: -2, beforeQty: 10, afterQty: 8, timestamp: DateTime.now().subtract(const Duration(hours: 8)), employeeName: 'Ahmed R.'),
  StockMovement(id: 'm3', productId: 'p5', productName: 'Thermal Paste 10g', type: MovementType.sale, quantity: -3, beforeQty: 3, afterQty: 0, timestamp: DateTime.now().subtract(const Duration(days: 2)), employeeName: 'Sara M.'),
  StockMovement(id: 'm4', productId: 'p3', productName: 'Industrial Cable 5m', type: MovementType.purchase, quantity: 100, beforeQty: 220, afterQty: 320, timestamp: DateTime.now().subtract(const Duration(days: 1)), employeeName: 'Khalid E.', notes: 'PO #PO-042'),
  StockMovement(id: 'm5', productId: 'p4', productName: 'LED Panel 60x60', type: MovementType.adjustment, quantity: -7, beforeQty: 10, afterQty: 3, timestamp: DateTime.now().subtract(const Duration(hours: 1)), employeeName: 'Omar B.', notes: 'Damaged units removed'),
  StockMovement(id: 'm6', productId: 'p6', productName: 'USB Hub 7-Port', type: MovementType.returnGoods, quantity: 2, beforeQty: 50, afterQty: 52, timestamp: DateTime.now().subtract(const Duration(days: 1)), employeeName: 'Ahmed R.', notes: 'Customer return'),
  StockMovement(id: 'm7', productId: 'p1', productName: 'Premium Widget Pro', type: MovementType.transfer, quantity: -10, beforeQty: 155, afterQty: 145, timestamp: DateTime.now().subtract(const Duration(days: 3)), employeeName: 'Khalid E.', notes: 'Transfer to Branch A'),
];
