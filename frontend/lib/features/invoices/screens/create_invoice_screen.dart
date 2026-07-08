// SmartBiz AI — Create Invoice screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/api/invoice_models.dart';
import '../../customers/customers_state.dart';
import '../../products/products_state.dart';
import '../invoices_state.dart';

class CreateInvoiceScreen extends StatefulWidget {
  const CreateInvoiceScreen({super.key});

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen> {
  String? _selectedContactId;
  final List<_LineItem> _items = [_LineItem()];
  bool _saving = false;
  String? _error;

  double get _subtotal => _items.fold(0.0, (s, i) => s + i.lineTotal);

  void _addItem() => setState(() => _items.add(_LineItem()));

  void _removeItem(int i) {
    if (_items.length > 1) setState(() => _items.removeAt(i));
  }

  Future<void> _save() async {
    if (_items.every((i) => i.productName.isEmpty && i.unitPrice <= 0)) {
      setState(() => _error = tr(context, 'inv_need_item'));
      return;
    }

    final validItems = _items
        .where((i) => i.unitPrice > 0 && i.quantity > 0)
        .map((i) => InvoiceItemPayload(
              productId: i.productId,
              quantity: i.quantity.toDouble(),
              unitPrice: i.unitPrice,
              productNameSnapshot: i.productName.isNotEmpty ? i.productName : null,
            ))
        .toList();

    if (validItems.isEmpty) {
      setState(() => _error = tr(context, 'inv_need_item'));
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      final payload = InvoicePayload(
        contactId: _selectedContactId,
        invoiceType: 'sale',
        items: validItems,
      );
      await context.read<InvoicesState>().createInvoice(payload);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'inv_saved')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      context.go('/invoices');
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
    final custState = context.watch<CustomersState>();
    final prodState = context.watch<ProductsState>();
    final isMobile = Responsive.isMobile(context);

    // Ensure customers and products are loaded
    if (custState.customers.isEmpty && !custState.loading) {
      Future.microtask(() => custState.loadCustomers(refresh: true));
    }
    if (prodState.all.isEmpty && !prodState.loading) {
      Future.microtask(() => prodState.loadProducts(refresh: true));
    }

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

              // ── Customer selector ─────────────────────────
              _SectionHeader(label: tr(context, 'inv_customer')),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.neutral300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedContactId,
                    isExpanded: true,
                    hint: Text(tr(context, 'inv_select_customer')),
                    items: custState.customers.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name),
                    )).toList(),
                    onChanged: (id) => setState(() => _selectedContactId = id),
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
                products: prodState.all,
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
                  Text(tr(context, 'inv_total'), style: AppTypography.headingSmall),
                  Text('\$${_subtotal.toStringAsFixed(2)}', style: AppTypography.headingSmall),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              const Divider(color: AppColors.divider),
              const SizedBox(height: AppSpacing.lg),

              // ── Actions ─────────────────────────────────
              if (_saving)
                const Center(child: Padding(
                  padding: EdgeInsets.all(AppSpacing.base),
                  child: CircularProgressIndicator(),
                ))
              else
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

/// Mutable line item for the create form.
class _LineItem {
  String? productId;
  String productName = '';
  int quantity = 1;
  double unitPrice = 0;

  double get lineTotal => quantity * unitPrice;
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
  final _LineItem item;
  final List<dynamic> products;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  const _ItemRow({required this.index, required this.item, required this.products, required this.onRemove, required this.onChanged});

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
          // Product name (text field, user can type freely)
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
                child: Text('\$${item.lineTotal.toStringAsFixed(2)}', style: AppTypography.labelMedium, textAlign: TextAlign.end),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
