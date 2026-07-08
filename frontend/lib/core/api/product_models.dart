// SmartBiz AI — Product API models.
//
// Maps backend /api/products responses and payloads.
// Handles numeric strings, nulls, and missing fields safely.

/// Product from backend API.
class ApiProduct {
  final String id;
  final String? categoryId;
  final String type;
  final String name;
  final String sku;
  final double basePrice;
  final double costPrice;
  final int minStockAlert;
  final Map<String, dynamic>? dynamicAttributes;
  final String? createdAt;
  final String? updatedAt;

  const ApiProduct({
    required this.id,
    this.categoryId,
    this.type = 'physical',
    required this.name,
    this.sku = '',
    this.basePrice = 0,
    this.costPrice = 0,
    this.minStockAlert = 0,
    this.dynamicAttributes,
    this.createdAt,
    this.updatedAt,
  });

  factory ApiProduct.fromJson(Map<String, dynamic> json) => ApiProduct(
        id: json['id'] as String? ?? '',
        categoryId: json['category_id'] as String?,
        type: json['type'] as String? ?? 'physical',
        name: json['name'] as String? ?? '',
        sku: json['sku'] as String? ?? '',
        basePrice: _toDouble(json['base_price']),
        costPrice: _toDouble(json['cost_price']),
        minStockAlert: _toInt(json['min_stock_alert']),
        dynamicAttributes: json['dynamic_attributes'] as Map<String, dynamic>?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
      );

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// Paginated list result from GET /api/products.
class ProductListResult {
  final List<ApiProduct> data;
  final int currentPage;
  final int lastPage;
  final int total;

  const ProductListResult({
    this.data = const [],
    this.currentPage = 1,
    this.lastPage = 1,
    this.total = 0,
  });

  factory ProductListResult.fromJson(Map<String, dynamic> json) {
    final dataList = json['data'] as List<dynamic>? ?? [];
    final meta = json['meta'] as Map<String, dynamic>? ?? {};

    return ProductListResult(
      data: dataList
          .whereType<Map<String, dynamic>>()
          .map(ApiProduct.fromJson)
          .toList(),
      currentPage: meta['current_page'] as int? ?? 1,
      lastPage: meta['last_page'] as int? ?? 1,
      total: meta['total'] as int? ?? dataList.length,
    );
  }

  bool get hasMore => currentPage < lastPage;
}

/// Payload for creating/updating a product.
class ProductPayload {
  final String name;
  final String? sku;
  final String type;
  final double basePrice;
  final double costPrice;
  final int minStockAlert;
  final String? categoryId;

  const ProductPayload({
    required this.name,
    this.sku,
    this.type = 'physical',
    required this.basePrice,
    this.costPrice = 0,
    this.minStockAlert = 0,
    this.categoryId,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (sku != null && sku!.isNotEmpty) 'sku': sku,
        'type': type,
        'base_price': basePrice,
        'cost_price': costPrice,
        'min_stock_alert': minStockAlert,
        if (categoryId != null) 'category_id': categoryId,
      };
}
