// SmartBiz AI — Inventory reusable widgets.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/inventory_models.dart';

class StockStatusBadge extends StatelessWidget {
  final StockStatus status;
  const StockStatusBadge({super.key, required this.status});

  Color get _color => switch (status) {
    StockStatus.inStock => AppColors.success,
    StockStatus.lowStock => AppColors.warning,
    StockStatus.outOfStock => AppColors.error,
  };
  String get _key => switch (status) {
    StockStatus.inStock => 'stk_in_stock',
    StockStatus.lowStock => 'stk_low_stock',
    StockStatus.outOfStock => 'stk_out_stock',
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(tr(context, _key), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _color)),
    ]),
  );
}

class MovementTypeBadge extends StatelessWidget {
  final MovementType type;
  const MovementTypeBadge({super.key, required this.type});

  Color get _color => switch (type) {
    MovementType.sale => AppColors.primary,
    MovementType.purchase => AppColors.success,
    MovementType.adjustment => AppColors.warning,
    MovementType.returnGoods => AppColors.info,
    MovementType.transfer => AppColors.accent,
  };
  String get _key => switch (type) {
    MovementType.sale => 'stk_mv_sale',
    MovementType.purchase => 'stk_mv_purchase',
    MovementType.adjustment => 'stk_mv_adjust',
    MovementType.returnGoods => 'stk_mv_return',
    MovementType.transfer => 'stk_mv_transfer',
  };
  IconData get _icon => switch (type) {
    MovementType.sale => Icons.shopping_cart_outlined,
    MovementType.purchase => Icons.add_shopping_cart,
    MovementType.adjustment => Icons.tune,
    MovementType.returnGoods => Icons.undo,
    MovementType.transfer => Icons.swap_horiz,
  };

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(_icon, size: 12, color: _color),
      const SizedBox(width: 4),
      Text(tr(context, _key), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _color)),
    ]),
  );
}

class WarehouseBadge extends StatelessWidget {
  final String name;
  const WarehouseBadge({super.key, required this.name});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(6)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.warehouse_outlined, size: 10, color: AppColors.neutral500),
      const SizedBox(width: 4),
      Text(name, style: const TextStyle(fontSize: 10, color: AppColors.neutral600, fontWeight: FontWeight.w500)),
    ]),
  );
}

class InventoryCard extends StatelessWidget {
  final InventoryItem item;
  final String warehouseName;
  final VoidCallback? onTap;
  const InventoryCard({super.key, required this.item, required this.warehouseName, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: item.status == StockStatus.outOfStock ? AppColors.error.withValues(alpha: 0.3) : item.status == StockStatus.lowStock ? AppColors.warning.withValues(alpha: 0.3) : AppColors.divider)),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.inventory_2_outlined, size: 20, color: AppColors.primary)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.productName, style: AppTypography.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(children: [
            if (item.sku != null) ...[Text(item.sku!, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)), const SizedBox(width: 8)],
            WarehouseBadge(name: warehouseName),
          ]),
        ])),
        const SizedBox(width: AppSpacing.sm),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${item.stockQty}', style: AppTypography.headingSmall.copyWith(color: item.status == StockStatus.outOfStock ? AppColors.error : item.status == StockStatus.lowStock ? AppColors.warning : AppColors.textPrimary)),
          StockStatusBadge(status: item.status),
        ]),
      ]),
    ),
  );
}

class MovementTile extends StatelessWidget {
  final StockMovement movement;
  const MovementTile({super.key, required this.movement});

  @override
  Widget build(BuildContext context) {
    final isPositive = movement.quantity > 0;
    final diff = DateTime.now().difference(movement.timestamp);
    final ago = diff.inDays > 0 ? '${diff.inDays}d' : diff.inHours > 0 ? '${diff.inHours}h' : '${diff.inMinutes}m';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: (isPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(isPositive ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: isPositive ? AppColors.success : AppColors.error)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(movement.productName, style: AppTypography.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(children: [MovementTypeBadge(type: movement.type), if (movement.employeeName != null) ...[const SizedBox(width: 6), Text(movement.employeeName!, style: AppTypography.caption)]]),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${isPositive ? "+" : ""}${movement.quantity}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isPositive ? AppColors.success : AppColors.error)),
          Text('${movement.beforeQty} → ${movement.afterQty}', style: AppTypography.caption),
          Text(ago, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}

class LowStockAlertCard extends StatelessWidget {
  final InventoryItem item;
  final VoidCallback? onRestock;
  const LowStockAlertCard({super.key, required this.item, this.onRestock});
  @override
  Widget build(BuildContext context) {
    final isOut = item.status == StockStatus.outOfStock;
    final color = isOut ? AppColors.error : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Icon(isOut ? Icons.error_outline : Icons.warning_amber, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.productName, style: AppTypography.labelMedium),
          Text('${tr(context, 'stk_stock')}: ${item.stockQty} / ${tr(context, 'stk_threshold')}: ${item.lowStockThreshold}', style: AppTypography.caption.copyWith(color: color)),
        ])),
        if (onRestock != null)
          TextButton(onPressed: onRestock, child: Text(tr(context, 'stk_restock'), style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}
