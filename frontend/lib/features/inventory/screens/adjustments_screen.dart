// SmartBiz AI — Inventory adjustments screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/api/inventory_models.dart';
import '../../../core/api/warehouse_models.dart';
import '../../products/products_state.dart';
import '../inventory_state.dart';

class AdjustmentsScreen extends StatefulWidget {
  const AdjustmentsScreen({super.key});
  @override
  State<AdjustmentsScreen> createState() => _AdjustmentsScreenState();
}

class _AdjustmentsScreenState extends State<AdjustmentsScreen> {
  String? _selectedProductId;
  String? _selectedWarehouseId;
  final _qtyC = TextEditingController();
  final _costC = TextEditingController();
  final _notesC = TextEditingController();
  String _movementType = 'adjustment_increase';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _qtyC.dispose();
    _costC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedProductId == null || _selectedWarehouseId == null || _qtyC.text.trim().isEmpty) {
      setState(() => _error = tr(context, 'stk_adj_required'));
      return;
    }
    final qty = double.tryParse(_qtyC.text.trim()) ?? 0;
    if (qty <= 0) {
      setState(() => _error = tr(context, 'stk_adj_required'));
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final payload = InventoryMovementPayload(
        warehouseId: _selectedWarehouseId!,
        productId: _selectedProductId!,
        movementType: _movementType,
        quantityChange: qty,
        unitCost: _costC.text.isNotEmpty ? double.tryParse(_costC.text) : null,
        reasonCode: _movementType,
        notes: _notesC.text.trim().isNotEmpty ? _notesC.text.trim() : null,
      );
      await context.read<InventoryState>().createMovement(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(context, 'stk_adj_success')),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      _qtyC.clear();
      _costC.clear();
      _notesC.clear();
      setState(() { _selectedProductId = null; _saving = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final invState = context.watch<InventoryState>();
    final prodState = context.watch<ProductsState>();
    final warehouses = invState.warehouses;

    // Ensure products loaded
    if (prodState.all.isEmpty && !prodState.loading) {
      Future.microtask(() => prodState.loadProducts(refresh: true));
    }

    // Auto-select first warehouse if only one
    if (_selectedWarehouseId == null && warehouses.length == 1) {
      Future.microtask(() => setState(() => _selectedWarehouseId = warehouses.first.id));
    }

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

          // Error banner
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error))),
              ]),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Warehouse selector
          if (warehouses.length > 1) ...[
            Text(tr(context, 'stk_warehouse'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _selectedWarehouseId,
              decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              hint: Text(tr(context, 'stk_select_warehouse')),
              items: warehouses.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
              onChanged: (v) => setState(() => _selectedWarehouseId = v),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Create warehouse inline if none exists
          if (warehouses.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.warehouse_outlined, size: 18, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, 'stk_no_warehouse'), style: AppTypography.bodySmall)),
                TextButton(
                  onPressed: () => _showCreateWarehouse(context, invState),
                  child: Text(tr(context, 'stk_create_warehouse')),
                ),
              ]),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          // Select product
          Text(tr(context, 'stk_adj_product'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _selectedProductId,
            decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            hint: Text(tr(context, 'stk_adj_select')),
            items: prodState.all.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
            onChanged: (v) => setState(() => _selectedProductId = v),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Movement type
          Text(tr(context, 'stk_adj_action'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: MovementTypes.userFacing.map((t) {
            final selected = _movementType == t;
            final isInc = MovementTypes.isIncrease(t);
            return ChoiceChip(
              label: Text(MovementTypes.label(t)),
              selected: selected,
              onSelected: (_) => setState(() => _movementType = t),
              selectedColor: (isInc ? AppColors.success : AppColors.error).withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            );
          }).toList()),
          const SizedBox(height: AppSpacing.lg),

          // Quantity
          Text(tr(context, 'stk_qty'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _qtyC, keyboardType: TextInputType.number, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
          const SizedBox(height: AppSpacing.lg),

          // Unit cost (optional)
          Text(tr(context, 'stk_unit_cost'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _costC, keyboardType: TextInputType.number, decoration: InputDecoration(hintText: tr(context, 'stk_optional'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
          const SizedBox(height: AppSpacing.lg),

          // Notes
          Text(tr(context, 'stk_adj_notes'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _notesC, maxLines: 2, decoration: InputDecoration(hintText: tr(context, 'stk_adj_notes_hint'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
          const SizedBox(height: AppSpacing.xl),

          // Actions
          if (_saving)
            const Center(child: Padding(padding: EdgeInsets.all(AppSpacing.base), child: CircularProgressIndicator()))
          else
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

  void _showCreateWarehouse(BuildContext context, InventoryState state) {
    final nameC = TextEditingController();
    final locC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(tr(context, 'stk_create_warehouse')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameC, decoration: InputDecoration(labelText: tr(context, 'stk_wh_name'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
          const SizedBox(height: AppSpacing.md),
          TextField(controller: locC, decoration: InputDecoration(labelText: tr(context, 'stk_wh_location'), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'stk_cancel'))),
          FilledButton(onPressed: () async {
            if (nameC.text.trim().isEmpty) return;
            try {
              await state.createWarehouse(
                  WarehousePayload(name: nameC.text.trim(), location: locC.text.trim().isNotEmpty ? locC.text.trim() : null));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                setState(() => _selectedWarehouseId = state.warehouses.last.id);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'stk_wh_saved')), backgroundColor: AppColors.success));
              }
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
              }
            }
          }, child: Text(tr(context, 'stk_create_warehouse'))),
        ],
      ),
    );
  }
}
