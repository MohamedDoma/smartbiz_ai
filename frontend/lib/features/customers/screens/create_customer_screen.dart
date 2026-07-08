// SmartBiz AI — Create customer screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../customers_state.dart';

class CreateCustomerScreen extends StatefulWidget {
  const CreateCustomerScreen({super.key});
  @override
  State<CreateCustomerScreen> createState() => _CreateCustomerScreenState();
}

class _CreateCustomerScreenState extends State<CreateCustomerScreen> {
  final _nameC = TextEditingController();
  final _companyC = TextEditingController();
  final _phoneC = TextEditingController();
  final _emailC = TextEditingController();
  final _addressC = TextEditingController();
  final _notesC = TextEditingController();
  final _taxC = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _nameC.dispose(); _companyC.dispose(); _phoneC.dispose(); _emailC.dispose(); _addressC.dispose(); _notesC.dispose(); _taxC.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_nameC.text.trim().isEmpty) {
      setState(() => _error = tr(context, 'cust_name_required'));
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      await context.read<CustomersState>().addCustomer(
        name: _nameC.text.trim(),
        company: _companyC.text.trim().isNotEmpty ? _companyC.text.trim() : null,
        phone: _phoneC.text.trim(),
        email: _emailC.text.trim().isNotEmpty ? _emailC.text.trim() : null,
        address: _addressC.text.trim().isNotEmpty ? _addressC.text.trim() : null,
        notes: _notesC.text.trim().isNotEmpty ? _notesC.text.trim() : null,
        taxNumber: _taxC.text.trim().isNotEmpty ? _taxC.text.trim() : null,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cust_created')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      context.go('/customers');
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ──────────────────────────────────────
          Row(children: [
            Container(
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: IconButton(
                onPressed: () => context.go('/customers'),
                icon: const Icon(Icons.arrow_back, size: 18),
                tooltip: tr(context, 'inv_cancel'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'cust_add'), style: AppTypography.headingSmall),
                Text(tr(context, 'cust_add_subtitle'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
              ],
            )),
          ]),
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

          // ── Contact Details ─────────────────────────────
          _SectionHeader(label: tr(context, 'cust_contact')),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _nameC, label: tr(context, 'cust_name'), required: true),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _companyC, label: tr(context, 'cust_company')),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _phoneC, label: tr(context, 'cust_phone'), keyboard: TextInputType.phone),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _emailC, label: tr(context, 'cust_email'), keyboard: TextInputType.emailAddress),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _addressC, label: tr(context, 'cust_address')),
          const SizedBox(height: AppSpacing.lg),

          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.lg),

          // ── Additional Info ─────────────────────────────
          _SectionHeader(label: tr(context, 'cust_additional_info')),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _taxC, label: tr(context, 'cust_tax_number')),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _notesC, label: tr(context, 'cust_notes'), maxLines: 3),
          const SizedBox(height: AppSpacing.xl),

          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.lg),

          // ── Actions ─────────────────────────────────────
          if (_saving)
            const Center(child: Padding(
              padding: EdgeInsets.all(AppSpacing.base),
              child: CircularProgressIndicator(),
            ))
          else
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => context.go('/customers'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(tr(context, 'inv_cancel')),
              )),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, size: 18),
                label: Text(tr(context, 'cust_save')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              )),
            ]),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController c; final String label; final bool required; final TextInputType? keyboard; final int maxLines;
  const _Field({required this.c, required this.label, this.required = false, this.keyboard, this.maxLines = 1});
  @override
  Widget build(BuildContext context) => TextField(
    controller: c, keyboardType: keyboard, maxLines: maxLines,
    decoration: InputDecoration(labelText: required ? '$label *' : label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
  );
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
