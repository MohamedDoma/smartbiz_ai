// SmartBiz AI — Create Invoice screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../invoices_state.dart';
import '../models/invoice_models.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  Customer? _selectedCustomer;
  final List<InvoiceItem> _items = [InvoiceItem(productName: '', quantity: 1, unitPrice: 0)];

  double get _subtotal => _items.fold(0.0, (s, i) => s + i.total);
  double get _tax => _subtotal * 0.15;
  double get _total => _subtotal + _tax;

  void _addItem() => setState(() => _items.add(InvoiceItem(productName: '', quantity: 1, unitPrice: 0)));
  void _removeItem(int i) { if (_items.length > 1) setState(() => _items.removeAt(i)); }

  void _save() {
    if (_selectedCustomer == null || _items.every((i) => i.productName.isEmpty)) return;
    final validItems = _items.where((i) => i.productName.isNotEmpty && i.unitPrice > 0).toList();
    if (validItems.isEmpty) return;
    context.read<InvoicesState>().createInvoice(_selectedCustomer!, validItems);
    context.go('/invoices');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InvoicesState>();
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.neutral100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      onPressed: () => context.go('/invoices'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      tooltip: tr(context, 'inv_cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'inv_create_title'), style: AppTypography.headingSmall),
                      Text(tr(context, 'inv_create_subtitle'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                    ],
                  )),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Customer ────────────────────────────────
              _SectionHeader(label: tr(context, 'inv_customer')),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.neutral300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Customer>(
                    value: _selectedCustomer,
                    isExpanded: true,
                    hint: Text(tr(context, 'inv_select_customer')),
                    items: state.customers.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
                    onChanged: (c) => setState(() => _selectedCustomer = c),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              const Divider(color: AppColors.divider),
              const SizedBox(height: AppSpacing.lg),

              // ── Line Items ──────────────────────────────
              Row(
                children: [
                  Expanded(child: _SectionHeader(label: tr(context, 'inv_items'))),
                  TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(tr(context, 'inv_add_item')),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              ..._items.asMap().entries.map((e) => _ItemRow(
                index: e.key,
                item: e.value,
                onRemove: () => _removeItem(e.key),
                onChanged: () => setState(() {}),
              )),

              const SizedBox(height: AppSpacing.lg),
              const Divider(color: AppColors.divider),
              const SizedBox(height: AppSpacing.lg),

              // ── Totals ──────────────────────────────────
              _SectionHeader(label: tr(context, 'inv_totals')),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr(context, 'inv_subtotal'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  Text('\$${_subtotal.toStringAsFixed(2)}', style: AppTypography.bodyMedium),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${tr(context, 'inv_tax')} (15%)', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                  Text('\$${_tax.toStringAsFixed(2)}', style: AppTypography.bodyMedium),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr(context, 'inv_total'), style: AppTypography.headingSmall),
                  Text('\$${_total.toStringAsFixed(2)}', style: AppTypography.headingSmall),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              const Divider(color: AppColors.divider),
              const SizedBox(height: AppSpacing.lg),

              // ── Actions ─────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go('/invoices'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text(tr(context, 'inv_cancel')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(tr(context, 'inv_save_draft')),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 3, height: 16,
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: AppSpacing.sm),
      Text(label, style: AppTypography.labelLarge.copyWith(color: AppColors.textSecondary)),
    ],
  );
}

class _ItemRow extends StatelessWidget {
  final int index;
  final InvoiceItem item;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  const _ItemRow({required this.index, required this.item, required this.onRemove, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('#${index + 1}', style: AppTypography.caption),
              const Spacer(),
              InkWell(onTap: onRemove, child: const Icon(Icons.close, size: 16, color: AppColors.error)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            onChanged: (v) { item.productName = v; onChanged(); },
            textDirection: Directionality.of(context),
            decoration: InputDecoration(
              labelText: tr(context, 'inv_product_name'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) { item.quantity = int.tryParse(v) ?? 1; onChanged(); },
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr(context, 'inv_qty'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  onChanged: (v) { item.unitPrice = double.tryParse(v) ?? 0; onChanged(); },
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr(context, 'inv_price'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 80,
                child: Text('\$${item.total.toStringAsFixed(2)}', style: AppTypography.labelMedium, textAlign: TextAlign.end),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
