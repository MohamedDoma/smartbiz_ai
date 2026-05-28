// SmartBiz AI — Inventory adjustments screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../inventory_state.dart';
import '../models/inventory_models.dart';

class AdjustmentsScreen extends StatefulWidget {
  const AdjustmentsScreen({super.key});
  @override
  State<AdjustmentsScreen> createState() => _AdjustmentsScreenState();
}

class _AdjustmentsScreenState extends State<AdjustmentsScreen> {
  String? _selectedProductId;
  final _qtyC = TextEditingController();
  final _notesC = TextEditingController();
  String _action = 'add'; // add, remove, set

  @override
  void dispose() { _qtyC.dispose(); _notesC.dispose(); super.dispose(); }

  void _submit() {
    if (_selectedProductId == null || _qtyC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'stk_adj_required')), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      return;
    }
    final state = context.read<InventoryState>();
    final qty = int.tryParse(_qtyC.text.trim()) ?? 0;
    if (qty <= 0) return;

    final item = state.getByProductId(_selectedProductId!);
    if (item == null) return;

    int delta;
    if (_action == 'add') {
      delta = qty;
    } else if (_action == 'remove') {
      delta = -qty;
    } else {
      delta = qty - item.stockQty; // set
    }

    state.adjustStock(productId: _selectedProductId!, delta: delta, reason: _action, notes: _notesC.text.trim().isNotEmpty ? _notesC.text.trim() : null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'stk_adj_success')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    _qtyC.clear();
    _notesC.clear();
    setState(() => _selectedProductId = null);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventoryState>();
    final allItems = state.items;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/inventory'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(tr(context, 'stk_adjust'), style: AppTypography.headingLarge)),
          ]),
          const SizedBox(height: AppSpacing.sm),
          Text(tr(context, 'stk_adj_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xl),

          // Select product
          Text(tr(context, 'stk_adj_product'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            value: _selectedProductId,
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            hint: Text(tr(context, 'stk_adj_select')),
            items: allItems.map((i) => DropdownMenuItem(value: i.productId, child: Text('${i.productName} (${i.stockQty})'))).toList(),
            onChanged: (v) => setState(() => _selectedProductId = v),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Action type
          Text(tr(context, 'stk_adj_action'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            ChoiceChip(label: Text(tr(context, 'stk_adj_add')), selected: _action == 'add', onSelected: (_) => setState(() => _action = 'add'), selectedColor: AppColors.success.withValues(alpha: 0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ChoiceChip(label: Text(tr(context, 'stk_adj_remove')), selected: _action == 'remove', onSelected: (_) => setState(() => _action = 'remove'), selectedColor: AppColors.error.withValues(alpha: 0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ChoiceChip(label: Text(tr(context, 'stk_adj_set')), selected: _action == 'set', onSelected: (_) => setState(() => _action = 'set'), selectedColor: AppColors.info.withValues(alpha: 0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // Quantity
          Text(tr(context, 'stk_qty'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _qtyC, keyboardType: TextInputType.number, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
          const SizedBox(height: AppSpacing.lg),

          // Notes
          Text(tr(context, 'stk_adj_notes'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _notesC, maxLines: 2, decoration: InputDecoration(hintText: tr(context, 'stk_adj_notes_hint'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
          const SizedBox(height: AppSpacing.xl),

          // Actions
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => context.go('/inventory'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: Text(tr(context, 'stk_cancel')))),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: FilledButton.icon(
              onPressed: _submit, icon: const Icon(Icons.check, size: 18), label: Text(tr(context, 'stk_adj_apply')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
          ]),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}
