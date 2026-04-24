// SmartBiz AI — Mock products data.
import '../models/product_models.dart';

class MockProducts {
  MockProducts._();

  static List<Product> products() => [
    Product(id: 'p1', name: 'Premium Coffee Beans', sku: 'COF-001', sellingPrice: 24.99, costPrice: 14.00, stock: 150, lowStockThreshold: 20),
    Product(id: 'p2', name: 'Premium Tea Box', sku: 'TEA-001', sellingPrice: 18.00, costPrice: 9.50, stock: 85, lowStockThreshold: 15),
    Product(id: 'p3', name: 'Sugar 1kg', sku: 'SUG-001', sellingPrice: 8.50, costPrice: 5.00, stock: 3, lowStockThreshold: 10),
    Product(id: 'p4', name: 'Paper Cups (100pc)', sku: 'CUP-001', sellingPrice: 15.00, costPrice: 8.00, stock: 0, lowStockThreshold: 5),
    Product(id: 'p5', name: 'Honey Jar 500g', sku: 'HON-001', sellingPrice: 22.50, costPrice: 15.00, stock: 42, lowStockThreshold: 10),
    Product(id: 'p6', name: 'Cleaning Solution 5L', sku: 'CLN-001', sellingPrice: 18.00, costPrice: 10.00, stock: 28, lowStockThreshold: 5),
    Product(id: 'p7', name: 'Ink Cartridge', sku: 'INK-001', sellingPrice: 35.00, costPrice: 22.00, stock: 8, lowStockThreshold: 10),
    Product(id: 'p8', name: 'Office Supplies Kit', sku: 'OFF-001', sellingPrice: 89.99, costPrice: 52.00, stock: 12, lowStockThreshold: 3),
    Product(id: 'p9', name: 'Fabric Roll (50m)', sku: 'FAB-001', sellingPrice: 120.00, costPrice: 75.00, stock: 5, lowStockThreshold: 2),
    Product(id: 'p10', name: 'Mop Pro', sku: 'MOP-001', sellingPrice: 25.00, costPrice: 13.00, stock: 0, lowStockThreshold: 3, status: ProductStatus.inactive),
  ];
}
