// SmartBiz AI — Create customer screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../customers_state.dart';
import '../models/customer_models.dart';

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
  CustomerStatus _status = CustomerStatus.active;
  String _lang = 'en';

  @override
  void dispose() { _nameC.dispose(); _companyC.dispose(); _phoneC.dispose(); _emailC.dispose(); _addressC.dispose(); _notesC.dispose(); super.dispose(); }

  void _save() {
    if (_nameC.text.trim().isEmpty || _phoneC.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cust_required')), backgroundColor: AppColors.error, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      return;
    }
    context.read<CustomersState>().addCustomer(
      name: _nameC.text.trim(),
      company: _companyC.text.trim().isNotEmpty ? _companyC.text.trim() : null,
      phone: _phoneC.text.trim(),
      email: _emailC.text.trim().isNotEmpty ? _emailC.text.trim() : null,
      address: _addressC.text.trim().isNotEmpty ? _addressC.text.trim() : null,
      notes: _notesC.text.trim().isNotEmpty ? _notesC.text.trim() : null,
      status: _status, langPref: _lang,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'cust_created')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
    context.go('/customers');
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

          // ── Contact Details ─────────────────────────────
          _SectionHeader(label: tr(context, 'cust_contact')),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _nameC, label: tr(context, 'cust_name'), required: true),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _companyC, label: tr(context, 'cust_company')),
          const SizedBox(height: AppSpacing.md),
          _Field(c: _phoneC, label: tr(context, 'cust_phone'), required: true, keyboard: TextInputType.phone),
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
          _Field(c: _notesC, label: tr(context, 'cust_notes'), maxLines: 3),
          const SizedBox(height: AppSpacing.lg),

          // Status
          Text(tr(context, 'cust_status'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            ChoiceChip(label: Text(tr(context, 'cust_active')), selected: _status == CustomerStatus.active, onSelected: (_) => setState(() => _status = CustomerStatus.active), selectedColor: AppColors.success.withValues(alpha: 0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ChoiceChip(label: Text(tr(context, 'cust_vip')), selected: _status == CustomerStatus.vip, onSelected: (_) => setState(() => _status = CustomerStatus.vip), selectedColor: AppColors.warning.withValues(alpha: 0.15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // Language
          Text(tr(context, 'cust_pref_lang'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(spacing: AppSpacing.sm, children: [
            ChoiceChip(label: const Text('English'), selected: _lang == 'en', onSelected: (_) => setState(() => _lang = 'en'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            ChoiceChip(label: const Text('عربي'), selected: _lang == 'ar', onSelected: (_) => setState(() => _lang = 'ar'), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
          ]),
          const SizedBox(height: AppSpacing.xl),

          const Divider(color: AppColors.divider),
          const SizedBox(height: AppSpacing.lg),

          // ── Actions ─────────────────────────────────────
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
