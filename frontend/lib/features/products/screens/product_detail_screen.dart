// SmartBiz AI — Product detail screen (real API).
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

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _editing = false;
  bool _saving = false;
  String? _error;

  // Edit controllers
  late TextEditingController _nameC;
  late TextEditingController _skuC;
  late TextEditingController _priceC;
  late TextEditingController _costC;
  late TextEditingController _threshC;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    _skuC = TextEditingController();
    _priceC = TextEditingController();
    _costC = TextEditingController();
    _threshC = TextEditingController();
  }

  @override
  void dispose() {
    _nameC.dispose(); _skuC.dispose(); _priceC.dispose();
    _costC.dispose(); _threshC.dispose();
    super.dispose();
  }

  void _startEdit(Product product) {
    _nameC.text = product.name;
    _skuC.text = product.sku;
    _priceC.text = product.sellingPrice.toStringAsFixed(2);
    _costC.text = product.costPrice.toStringAsFixed(2);
    _threshC.text = product.lowStockThreshold.toString();
    setState(() { _editing = true; _error = null; });
  }

  void _cancelEdit() => setState(() { _editing = false; _error = null; });

  Future<void> _saveEdit() async {
    if (_nameC.text.trim().isEmpty || _priceC.text.trim().isEmpty) {
      setState(() => _error = tr(context, 'prod_validation_required'));
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      await context.read<ProductsState>().updateProduct(
        id: widget.productId,
        name: _nameC.text.trim(),
        sku: _skuC.text.trim(),
        sellingPrice: double.tryParse(_priceC.text) ?? 0,
        costPrice: double.tryParse(_costC.text) ?? 0,
        minStockAlert: int.tryParse(_threshC.text) ?? 0,
      );
      if (!mounted) return;
      setState(() { _editing = false; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'prod_saved')), duration: const Duration(seconds: 1)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _saving = false; _error = e.toString().replaceAll('Exception: ', ''); });
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(ctx, 'prod_delete_title')),
        content: Text(tr(ctx, 'prod_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'inv_cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(tr(ctx, 'prod_delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<ProductsState>().deleteProduct(widget.productId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'prod_deleted'))),
      );
      context.go('/products');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProductsState>();
    final product = state.getById(widget.productId);
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
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18, color: AppColors.error),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(_error!, style: AppTypography.bodySmall.copyWith(color: AppColors.error))),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Info card / Edit form
              _editing ? _buildEditForm(context) : _buildInfoCard(context, product),
              const SizedBox(height: AppSpacing.xl),

              // Actions
              if (!_editing)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _startEdit(product),
                        icon: const Icon(Icons.edit, size: 16),
                        label: Text(tr(context, 'prod_edit')),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _confirmDelete,
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                        label: Text(tr(context, 'prod_delete'), style: const TextStyle(color: AppColors.error)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: const BorderSide(color: AppColors.error),
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

  Widget _buildInfoCard(BuildContext context, Product product) {
    return Container(
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
          _InfoRow(label: tr(context, 'prod_threshold'), value: '${product.lowStockThreshold}'),
          const SizedBox(height: AppSpacing.md),
          StockBadge(product: product),
        ],
      ),
    );
  }

  Widget _buildEditForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit, size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(tr(context, 'prod_edit'), style: AppTypography.labelLarge.copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _EditField(controller: _nameC, label: tr(context, 'prod_name'), context: context),
          const SizedBox(height: AppSpacing.md),
          _EditField(controller: _skuC, label: tr(context, 'prod_sku'), context: context),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _EditField(controller: _priceC, label: tr(context, 'prod_selling_price'), isNum: true, context: context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _EditField(controller: _costC, label: tr(context, 'prod_cost_price'), isNum: true, context: context)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _EditField(controller: _threshC, label: tr(context, 'prod_threshold'), isNum: true, context: context),
          const SizedBox(height: AppSpacing.lg),
          if (_saving)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _cancelEdit, child: Text(tr(context, 'inv_cancel')))),
                const SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: FilledButton.icon(
                  onPressed: _saveEdit,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(tr(context, 'prod_save')),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                )),
              ],
            ),
        ],
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

class _EditField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isNum;
  final BuildContext context;
  const _EditField({required this.controller, required this.label, this.isNum = false, required this.context});
  @override
  Widget build(BuildContext _) => TextField(
    controller: controller,
    textDirection: Directionality.of(context),
    keyboardType: isNum ? TextInputType.number : TextInputType.text,
    decoration: InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}
