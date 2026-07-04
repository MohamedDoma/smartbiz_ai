// SmartBiz AI — Inventory overview screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../inventory_state.dart';
import '../models/inventory_models.dart';
import '../widgets/inventory_widgets.dart';

class InventoryOverviewScreen extends StatelessWidget {
  const InventoryOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryState>();
    final isMobile = Responsive.isMobile(context);
    final alerts = [...state.outOfStockItems, ...state.lowStockItems];
    final items = state.items;

    return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Header
                Row(children: [
                  Expanded(child: Text(tr(context, 'stk_title'), style: AppTypography.headingLarge)),
                  OutlinedButton.icon(
                    onPressed: () => context.go('/inventory/movements'),
                    icon: const Icon(Icons.swap_vert, size: 16), label: Text(tr(context, 'stk_movements')),
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton.icon(
                    onPressed: () => context.go('/inventory/adjustments'),
                    icon: const Icon(Icons.tune, size: 16), label: Text(tr(context, 'stk_adjust')),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ]),
                const SizedBox(height: AppSpacing.lg),

                // Summary metrics
                Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                  _MetricChip(label: '${state.totalProducts} ${tr(context, 'stk_products')}', color: AppColors.primary, icon: Icons.inventory_2),
                  _MetricChip(label: '${state.totalUnits} ${tr(context, 'stk_units')}', color: AppColors.success, icon: Icons.stacked_bar_chart),
                  _MetricChip(label: '${state.lowStockCount} ${tr(context, 'stk_low_stock')}', color: AppColors.warning, icon: Icons.warning_amber),
                  _MetricChip(label: '${state.outOfStockCount} ${tr(context, 'stk_out_stock')}', color: AppColors.error, icon: Icons.error_outline),
                ]),
                const SizedBox(height: AppSpacing.xl),

                // Alerts
                if (alerts.isNotEmpty) ...[
                  Row(children: [
                    const Icon(Icons.notifications_active, size: 18, color: AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Text(tr(context, 'stk_alerts'), style: AppTypography.headingSmall),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  ...alerts.map((item) => LowStockAlertCard(item: item, onRestock: () => _showRestockDialog(context, state, item))),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // AI placeholder
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.accent.withValues(alpha: 0.12))),
                  child: Row(children: [
                    const Icon(Icons.auto_awesome, size: 18, color: AppColors.accent),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(tr(context, 'stk_ai_placeholder'), style: AppTypography.bodySmall.copyWith(color: AppColors.accent))),
                  ]),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Search + filters
                TextField(onChanged: state.setSearch, decoration: InputDecoration(
                  hintText: tr(context, 'stk_search'), prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
                  isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                )),
                const SizedBox(height: AppSpacing.md),

                // Filter row
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                  _FChip(label: tr(context, 'cust_all'), selected: state.statusFilter == null && state.warehouseFilter == null, onTap: () { state.setStatusFilter(null); state.setWarehouseFilter(null); }),
                  _FChip(label: tr(context, 'stk_low_stock'), selected: state.statusFilter == StockStatus.lowStock, onTap: () => state.setStatusFilter(state.statusFilter == StockStatus.lowStock ? null : StockStatus.lowStock)),
                  _FChip(label: tr(context, 'stk_out_stock'), selected: state.statusFilter == StockStatus.outOfStock, onTap: () => state.setStatusFilter(state.statusFilter == StockStatus.outOfStock ? null : StockStatus.outOfStock)),
                  const SizedBox(width: 8),
                  ...state.warehouses.map((w) => _FChip(label: w.name, selected: state.warehouseFilter == w.id, onTap: () => state.setWarehouseFilter(state.warehouseFilter == w.id ? null : w.id))),
                ])),
                const SizedBox(height: AppSpacing.lg),
              ]),
            ),
          ),

          // Inventory items — virtualized
          if (items.isEmpty)
            SliverFillRemaining(hasScrollBody: false,
              child: Center(child: Padding(padding: const EdgeInsets.all(AppSpacing.xxl), child: Text(tr(context, 'stk_empty'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)))))
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? AppSpacing.md : AppSpacing.base),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, i) => InventoryCard(item: items[i], warehouseName: state.warehouseName(items[i].warehouseId)),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    ));
  }

  void _showRestockDialog(BuildContext context, InventoryState state, InventoryItem item) {
    final qtyC = TextEditingController(text: '${item.lowStockThreshold * 2}');
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text('${tr(context, 'stk_restock')}: ${item.productName}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${tr(context, 'stk_current_stock')}: ${item.stockQty}', style: AppTypography.bodySmall),
        const SizedBox(height: AppSpacing.md),
        TextField(controller: qtyC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr(context, 'stk_qty'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
        FilledButton(onPressed: () {
          final qty = int.tryParse(qtyC.text) ?? 0;
          if (qty > 0) {
            state.adjustStock(productId: item.productId, delta: qty, reason: 'Restock');
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'stk_restocked')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
          }
        }, child: Text(tr(context, 'stk_restock'))),
      ],
    ));
  }
}

class _MetricChip extends StatelessWidget {
  final String label; final Color color; final IconData icon;
  const _MetricChip({required this.label, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.15))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 16, color: color), const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    ]),
  );
}

class _FChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _FChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSpacing.sm),
    child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap(),
      selectedColor: AppColors.primary.withValues(alpha: 0.12), checkmarkColor: AppColors.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: selected ? AppColors.primary : AppColors.neutral300)),
  );
}
