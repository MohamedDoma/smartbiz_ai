// SmartBiz AI — Product data models.

/// Product status.
enum ProductStatus { active, inactive }

/// Stock level indicator.
enum StockLevel { normal, low, outOfStock }

/// A single product.
class Product {
  final String id;
  String name;
  String sku;
  double sellingPrice;
  double costPrice;
  int stock;
  int lowStockThreshold;
  ProductStatus status;

  Product({
    required this.id,
    required this.name,
    this.sku = '',
    required this.sellingPrice,
    this.costPrice = 0,
    this.stock = 0,
    this.lowStockThreshold = 5,
    this.status = ProductStatus.active,
  });

  StockLevel get stockLevel {
    if (stock <= 0) return StockLevel.outOfStock;
    if (stock <= lowStockThreshold) return StockLevel.low;
    return StockLevel.normal;
  }

  double get margin => sellingPrice > 0 && costPrice > 0
      ? ((sellingPrice - costPrice) / sellingPrice * 100)
      : 0;
}
