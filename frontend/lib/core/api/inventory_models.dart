// SmartBiz AI — Inventory movement API models.
//
// Maps backend /api/inventory-movements responses and payloads.

/// Inventory movement from backend API.
class ApiInventoryMovement {
  final String id;
  final String? warehouseId;
  final String? warehouseName;
  final String? productId;
  final String? productName;
  final String? productSku;
  final String movementType;
  final double quantityChange;
  final double quantityBefore;
  final double quantityAfter;
  final double? unitCost;
  final double? totalCost;
  final String? referenceType;
  final String? referenceId;
  final String? reasonCode;
  final String? notes;
  final String? createdAt;

  const ApiInventoryMovement({
    required this.id,
    this.warehouseId,
    this.warehouseName,
    this.productId,
    this.productName,
    this.productSku,
    this.movementType = 'adjustment_increase',
    this.quantityChange = 0,
    this.quantityBefore = 0,
    this.quantityAfter = 0,
    this.unitCost,
    this.totalCost,
    this.referenceType,
    this.referenceId,
    this.reasonCode,
    this.notes,
    this.createdAt,
  });

  factory ApiInventoryMovement.fromJson(Map<String, dynamic> json) {
    // Warehouse may be nested object
    final wh = json['warehouse'] as Map<String, dynamic>?;
    // Product may be nested object
    final pr = json['product'] as Map<String, dynamic>?;

    return ApiInventoryMovement(
      id: json['id'] as String? ?? '',
      warehouseId: json['warehouse_id'] as String?,
      warehouseName: wh?['name'] as String?,
      productId: json['product_id'] as String?,
      productName: pr?['name'] as String?,
      productSku: pr?['sku'] as String?,
      movementType: json['movement_type'] as String? ?? 'adjustment_increase',
      quantityChange: _toDouble(json['quantity_change']),
      quantityBefore: _toDouble(json['quantity_before']),
      quantityAfter: _toDouble(json['quantity_after']),
      unitCost: json['unit_cost'] != null ? _toDouble(json['unit_cost']) : null,
      totalCost: json['total_cost'] != null ? _toDouble(json['total_cost']) : null,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as String?,
      reasonCode: json['reason_code'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// Paginated result from GET /api/inventory-movements.
class InventoryMovementListResult {
  final List<ApiInventoryMovement> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const InventoryMovementListResult({
    this.data = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
  });

  factory InventoryMovementListResult.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return InventoryMovementListResult(
      data: dataList
          .whereType<Map<String, dynamic>>()
          .map(ApiInventoryMovement.fromJson)
          .toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      total: meta['total'] as int? ?? dataList.length,
    );
  }
}

/// Inventory level (stock per product/warehouse) from /api/inventory-movements/levels.
class InventoryLevel {
  final String warehouseId;
  final String warehouseName;
  final String productId;
  final String productName;
  final String? sku;
  final double currentStock;
  final double? minStockAlert;
  final bool lowStock;

  const InventoryLevel({
    required this.warehouseId,
    required this.warehouseName,
    required this.productId,
    required this.productName,
    this.sku,
    this.currentStock = 0,
    this.minStockAlert,
    this.lowStock = false,
  });

  factory InventoryLevel.fromJson(Map<String, dynamic> json) => InventoryLevel(
        warehouseId: json['warehouse_id'] as String? ?? '',
        warehouseName: json['warehouse_name'] as String? ?? '',
        productId: json['product_id'] as String? ?? '',
        productName: json['product_name'] as String? ?? '',
        sku: json['sku'] as String?,
        currentStock: _toDouble(json['current_stock']),
        minStockAlert: json['min_stock_alert'] != null
            ? _toDouble(json['min_stock_alert'])
            : null,
        lowStock: json['low_stock'] as bool? ?? false,
      );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}

/// Payload for creating an inventory movement.
class InventoryMovementPayload {
  final String warehouseId;
  final String productId;
  final String movementType;
  final double quantityChange;
  final double? unitCost;
  final String? referenceType;
  final String? referenceId;
  final String? reasonCode;
  final String? notes;

  const InventoryMovementPayload({
    required this.warehouseId,
    required this.productId,
    required this.movementType,
    required this.quantityChange,
    this.unitCost,
    this.referenceType,
    this.referenceId,
    this.reasonCode,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'warehouse_id': warehouseId,
        'product_id': productId,
        'movement_type': movementType,
        'quantity_change': quantityChange,
        if (unitCost != null) 'unit_cost': unitCost,
        if (referenceType != null) 'reference_type': referenceType,
        if (referenceId != null) 'reference_id': referenceId,
        if (reasonCode != null && reasonCode!.isNotEmpty) 'reason_code': reasonCode,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

/// Allowed movement types from backend validation.
class MovementTypes {
  static const increase = [
    'purchase_receipt',
    'return_restock',
    'adjustment_increase',
    'transfer_in',
    'production_output',
    'opening_balance',
  ];

  static const decrease = [
    'sale_shipment',
    'return_dispose',
    'supplier_return',
    'adjustment_decrease',
    'transfer_out',
    'production_consume',
    'damage',
    'shrinkage',
    'expired',
  ];

  static List<String> get all => [...increase, ...decrease];

  /// User-friendly subset for manual adjustments.
  static const userFacing = [
    'adjustment_increase',
    'adjustment_decrease',
    'purchase_receipt',
    'opening_balance',
    'damage',
    'shrinkage',
  ];

  static String label(String type) => switch (type) {
        'purchase_receipt' => 'Purchase Receipt',
        'sale_shipment' => 'Sale Shipment',
        'return_restock' => 'Return (Restock)',
        'return_dispose' => 'Return (Dispose)',
        'supplier_return' => 'Supplier Return',
        'adjustment_increase' => 'Adjustment (+)',
        'adjustment_decrease' => 'Adjustment (-)',
        'transfer_out' => 'Transfer Out',
        'transfer_in' => 'Transfer In',
        'production_consume' => 'Production Consume',
        'production_output' => 'Production Output',
        'opening_balance' => 'Opening Balance',
        'damage' => 'Damage',
        'shrinkage' => 'Shrinkage',
        'expired' => 'Expired',
        _ => type.replaceAll('_', ' '),
      };

  static bool isIncrease(String type) => increase.contains(type);
}
