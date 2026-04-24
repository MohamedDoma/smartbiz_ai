// SmartBiz AI — Product detail screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../products_state.dart';
import '../models/product_models.dart';
import '../widgets/product_widgets.dart';

class ProductDetailScreen extends StatelessWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProductsState>();
    final product = state.getById(productId);
    final isMobile = Responsive.isMobile(context);

    if (product == null) {
      return Center(child: Text(tr(context, 'prod_not_found'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(onPressed: () => context.go('/products'), icon: const Icon(Icons.arrow_back)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(product.name, style: AppTypography.headingLarge),
                      if (product.sku.isNotEmpty) Text(product.sku, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ),
                  ProductStatusBadge(status: product.status),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Info card
              Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'prod_details'), style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.md),
                    _InfoRow(label: tr(context, 'prod_selling_price'), value: '\$${product.sellingPrice.toStringAsFixed(2)}'),
                    _InfoRow(label: tr(context, 'prod_cost_price'), value: product.costPrice > 0 ? '\$${product.costPrice.toStringAsFixed(2)}' : '—'),
                    if (product.margin > 0)
                      _InfoRow(label: tr(context, 'prod_margin'), value: '${product.margin.toStringAsFixed(1)}%'),
                    const Divider(height: AppSpacing.xl),
                    Text(tr(context, 'prod_inventory'), style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(child: _StockCard(label: tr(context, 'prod_current_stock'), value: '${product.stock}', level: product.stockLevel)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: _StockCard(label: tr(context, 'prod_threshold'), value: '${product.lowStockThreshold}', level: StockLevel.normal)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    StockBadge(product: product),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Stock adjustment
              Container(
                padding: const EdgeInsets.all(AppSpacing.base),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, 'prod_adjust_stock'), style: AppTypography.labelLarge),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StockBtn(icon: Icons.remove, color: AppColors.error, onTap: () => state.updateStock(product.id, -1)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                          child: Text('${product.stock}', style: AppTypography.headingLarge),
                        ),
                        _StockBtn(icon: Icons.add, color: AppColors.success, onTap: () => state.updateStock(product.id, 1)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => state.toggleStatus(product.id),
                      icon: Icon(product.status == ProductStatus.active ? Icons.block : Icons.check_circle, size: 16),
                      label: Text(tr(context, product.status == ProductStatus.active ? 'prod_deactivate' : 'prod_activate')),
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label; final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
      Text(value, style: AppTypography.labelMedium),
    ]),
  );
}

class _StockCard extends StatelessWidget {
  final String label; final String value; final StockLevel level;
  const _StockCard({required this.label, required this.value, required this.level});
  Color get _color => switch (level) { StockLevel.normal => AppColors.success, StockLevel.low => AppColors.warning, StockLevel.outOfStock => AppColors.error };
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: _color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: _color.withValues(alpha: 0.2))),
    child: Column(children: [
      Text(value, style: AppTypography.headingLarge.copyWith(color: _color)),
      const SizedBox(height: 2),
      Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
    ]),
  );
}

class _StockBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _StockBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Icon(icon, color: color, size: 20),
    ),
  );
}
