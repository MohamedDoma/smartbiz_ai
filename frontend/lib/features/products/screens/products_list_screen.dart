// SmartBiz AI — Products list screen.
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

class ProductsListScreen extends StatelessWidget {
  const ProductsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProductsState>();
    final isMobile = Responsive.isMobile(context);
    final products = state.filtered;
    final lowCount = state.lowStockCount;

    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(bottom: BorderSide(color: AppColors.divider))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(tr(context, 'prod_title'), style: AppTypography.headingLarge)),
                  if (lowCount > 0)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.warning_amber, size: 14, color: AppColors.warning),
                            const SizedBox(width: 4),
                            Text('$lowCount ${tr(context, 'prod_alerts')}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.warning)),
                          ],
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => context.go('/products/create'),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(tr(context, 'prod_add')),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                onChanged: state.setSearch,
                textDirection: Directionality.of(context),
                decoration: InputDecoration(
                  hintText: tr(context, 'prod_search'),
                  hintTextDirection: Directionality.of(context),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(label: tr(context, 'inv_all'), selected: state.stockFilter == null, onTap: () => state.setStockFilter(null)),
                    _FilterChip(label: tr(context, 'prod_stock_ok'), selected: state.stockFilter == StockLevel.normal, onTap: () => state.setStockFilter(StockLevel.normal)),
                    _FilterChip(label: tr(context, 'prod_stock_low'), selected: state.stockFilter == StockLevel.low, onTap: () => state.setStockFilter(StockLevel.low)),
                    _FilterChip(label: tr(context, 'prod_stock_out'), selected: state.stockFilter == StockLevel.outOfStock, onTap: () => state.setStockFilter(StockLevel.outOfStock)),
                  ],
                ),
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: products.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.neutral300),
                    const SizedBox(height: AppSpacing.md),
                    Text(tr(context, 'prod_empty'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  ]),
                )
              : ListView.separated(
                  padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _ProductRow(product: products[i]),
                ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: FilterChip(
        label: Text(label),
        selected: selected, onSelected: (_) => onTap(),
        selectedColor: AppColors.primarySurface, checkmarkColor: AppColors.primary,
        side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: selected ? AppColors.primary : AppColors.textSecondary),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Product product;
  const _ProductRow({required this.product});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go('/products/${product.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.inventory_2, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: AppTypography.labelLarge),
                  const SizedBox(height: 2),
                  Text(product.sku.isNotEmpty ? product.sku : '—', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('\$${product.sellingPrice.toStringAsFixed(2)}', style: AppTypography.labelLarge),
                const SizedBox(height: 4),
                StockBadge(product: product),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
