// SmartBiz AI — Products shared widgets.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../models/product_models.dart';

/// Color-coded stock badge.
class StockBadge extends StatelessWidget {
  final Product product;
  const StockBadge({super.key, required this.product});

  Color get _color => switch (product.stockLevel) {
    StockLevel.normal => AppColors.success,
    StockLevel.low => AppColors.warning,
    StockLevel.outOfStock => AppColors.error,
  };

  String _key() => switch (product.stockLevel) {
    StockLevel.normal => 'prod_stock_ok',
    StockLevel.low => 'prod_stock_low',
    StockLevel.outOfStock => 'prod_stock_out',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text('${product.stock} — ${tr(context, _key())}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color)),
        ],
      ),
    );
  }
}

/// Product status indicator.
class ProductStatusBadge extends StatelessWidget {
  final ProductStatus status;
  const ProductStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == ProductStatus.active;
    final color = isActive ? AppColors.success : AppColors.neutral500;
    final key = isActive ? 'prod_active' : 'prod_inactive';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(tr(context, key), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
