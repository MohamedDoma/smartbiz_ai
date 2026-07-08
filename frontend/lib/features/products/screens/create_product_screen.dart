// SmartBiz AI — Create Product screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../products_state.dart';

class CreateProductScreen extends StatefulWidget {
  const CreateProductScreen({super.key});

  @override
  State<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<CreateProductScreen> {
  final _nameC = TextEditingController();
  final _skuC = TextEditingController();
  final _priceC = TextEditingController();
  final _costC = TextEditingController();
  final _threshC = TextEditingController(text: '0');
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _nameC.dispose(); _skuC.dispose(); _priceC.dispose(); _costC.dispose(); _threshC.dispose(); super.dispose(); }

  Future<void> _save({bool addAnother = false}) async {
    if (_nameC.text.trim().isEmpty || _priceC.text.trim().isEmpty) {
      setState(() => _error = tr(context, 'prod_validation_required'));
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      await context.read<ProductsState>().createProduct(
        name: _nameC.text.trim(),
        sku: _skuC.text.trim(),
        sellingPrice: double.tryParse(_priceC.text) ?? 0,
        costPrice: double.tryParse(_costC.text) ?? 0,
        minStockAlert: int.tryParse(_threshC.text) ?? 0,
      );

      if (!mounted) return;

      if (addAnother) {
        _nameC.clear(); _skuC.clear(); _priceC.clear(); _costC.clear(); _threshC.text = '0';
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(context, 'prod_saved')), duration: const Duration(seconds: 1)),
        );
      } else {
        context.go('/products');
      }
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
    final isMobile = Responsive.isMobile(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
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
                      onPressed: () => context.go('/products'),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      tooltip: tr(context, 'inv_cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, 'prod_create_title'), style: AppTypography.headingSmall),
                      Text(tr(context, 'prod_create_subtitle'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
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

              // ── Product Info ────────────────────────────
              _SectionHeader(label: tr(context, 'prod_details')),
              const SizedBox(height: AppSpacing.md),
              _Field(controller: _nameC, label: tr(context, 'prod_name'), context: context),
              const SizedBox(height: AppSpacing.md),
              _Field(controller: _skuC, label: tr(context, 'prod_sku'), context: context),
              const SizedBox(height: AppSpacing.lg),

              const Divider(color: AppColors.divider),
              const SizedBox(height: AppSpacing.lg),

              // ── Pricing ─────────────────────────────────
              _SectionHeader(label: tr(context, 'prod_pricing')),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: _Field(controller: _priceC, label: tr(context, 'prod_selling_price'), isNum: true, context: context)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: _Field(controller: _costC, label: tr(context, 'prod_cost_price'), isNum: true, context: context)),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              const Divider(color: AppColors.divider),
              const SizedBox(height: AppSpacing.lg),

              // ── Stock Alert ──────────────────────────────
              _SectionHeader(label: tr(context, 'prod_inventory')),
              const SizedBox(height: AppSpacing.md),
              _Field(controller: _threshC, label: tr(context, 'prod_threshold'), isNum: true, context: context),
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
                        onPressed: () => _save(addAnother: true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(tr(context, 'prod_save_add')),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.check, size: 18),
                        label: Text(tr(context, 'prod_save')),
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

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool isNum;
  final BuildContext context;
  const _Field({required this.controller, required this.label, this.isNum = false, required this.context});

  @override
  Widget build(BuildContext _) {
    return TextField(
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
}
