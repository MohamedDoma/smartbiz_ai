// SmartBiz AI — Customer detail screen (real API).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../customers_state.dart';
import '../models/customer_models.dart';
import '../widgets/customer_widgets.dart';

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _editing = false;
  bool _saving = false;
  String? _error;

  late TextEditingController _nameC;
  late TextEditingController _phoneC;
  late TextEditingController _emailC;
  late TextEditingController _addressC;
  late TextEditingController _taxC;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController();
    _phoneC = TextEditingController();
    _emailC = TextEditingController();
    _addressC = TextEditingController();
    _taxC = TextEditingController();
  }

  @override
  void dispose() {
    _nameC.dispose(); _phoneC.dispose(); _emailC.dispose();
    _addressC.dispose(); _taxC.dispose();
    super.dispose();
  }

  void _startEdit(Customer c) {
    _nameC.text = c.name;
    _phoneC.text = c.phone;
    _emailC.text = c.email ?? '';
    _addressC.text = c.address ?? '';
    _taxC.text = '';
    setState(() { _editing = true; _error = null; });
  }

  void _cancelEdit() => setState(() { _editing = false; _error = null; });

  Future<void> _saveEdit() async {
    if (_nameC.text.trim().isEmpty) {
      setState(() => _error = tr(context, 'cust_name_required'));
      return;
    }

    setState(() { _saving = true; _error = null; });

    try {
      await context.read<CustomersState>().updateCustomer(
        id: widget.customerId,
        name: _nameC.text.trim(),
        phone: _phoneC.text.trim().isNotEmpty ? _phoneC.text.trim() : null,
        email: _emailC.text.trim().isNotEmpty ? _emailC.text.trim() : null,
        address: _addressC.text.trim().isNotEmpty ? _addressC.text.trim() : null,
        taxNumber: _taxC.text.trim().isNotEmpty ? _taxC.text.trim() : null,
      );
      if (!mounted) return;
      setState(() { _editing = false; _saving = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cust_saved')), backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
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
        title: Text(tr(ctx, 'cust_delete_title')),
        content: Text(tr(ctx, 'cust_delete_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr(ctx, 'inv_cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(tr(ctx, 'cust_delete')),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await context.read<CustomersState>().deleteCustomer(widget.customerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'cust_deleted'))),
      );
      context.go('/customers');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CustomersState>();
    final c = state.getById(widget.customerId);
    final isMobile = Responsive.isMobile(context);

    if (c == null) {
      return Center(child: Text(tr(context, 'cust_not_found'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)));
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 800),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Back + header
          Row(children: [
            IconButton(onPressed: () => context.go('/customers'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            CircleAvatar(radius: 22, backgroundColor: c.status == CustomerStatus.vip ? AppColors.warning.withValues(alpha: 0.15) : AppColors.primarySurface,
              child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : '?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.status == CustomerStatus.vip ? AppColors.warning : AppColors.primary))),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: AppTypography.headingLarge),
              if (c.company != null) Text(c.company!, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            CustomerStatusBadge(status: c.status),
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

          // Stats row
          _StatsRow(customer: c),
          const SizedBox(height: AppSpacing.xl),

          // Info card or edit form
          _editing ? _buildEditForm(context) : _buildInfoCard(context, c),
          const SizedBox(height: AppSpacing.xl),

          // Actions
          if (!_editing) ...[
            Text(tr(context, 'cust_actions'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
              _ActionBtn(icon: Icons.edit, label: tr(context, 'cust_edit'), color: AppColors.primary, onTap: () => _startEdit(c)),
              _ActionBtn(icon: Icons.receipt_long, label: tr(context, 'cust_create_inv'), color: AppColors.accent, onTap: () => context.go('/invoices/create')),
              _ActionBtn(icon: Icons.delete_outline, label: tr(context, 'cust_delete'), color: AppColors.error, onTap: _confirmDelete),
            ]),
          ],
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  Widget _buildInfoCard(BuildContext context, Customer c) {
    return _Section(title: tr(context, 'cust_contact'), children: [
      _InfoRow(icon: Icons.phone, label: tr(context, 'cust_phone'), value: c.phone.isNotEmpty ? c.phone : '—'),
      if (c.email != null) _InfoRow(icon: Icons.email, label: tr(context, 'cust_email'), value: c.email!),
      if (c.address != null) _InfoRow(icon: Icons.location_on, label: tr(context, 'cust_address'), value: c.address!),
    ]);
  }

  Widget _buildEditForm(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.primary.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.edit, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(tr(context, 'cust_edit'), style: AppTypography.labelLarge.copyWith(color: AppColors.primary)),
        ]),
        const SizedBox(height: AppSpacing.md),
        _EditField(c: _nameC, label: tr(context, 'cust_name')),
        const SizedBox(height: AppSpacing.md),
        _EditField(c: _phoneC, label: tr(context, 'cust_phone'), keyboard: TextInputType.phone),
        const SizedBox(height: AppSpacing.md),
        _EditField(c: _emailC, label: tr(context, 'cust_email'), keyboard: TextInputType.emailAddress),
        const SizedBox(height: AppSpacing.md),
        _EditField(c: _addressC, label: tr(context, 'cust_address')),
        const SizedBox(height: AppSpacing.md),
        _EditField(c: _taxC, label: tr(context, 'cust_tax_number')),
        const SizedBox(height: AppSpacing.lg),
        if (_saving)
          const Center(child: CircularProgressIndicator())
        else
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _cancelEdit, child: Text(tr(context, 'inv_cancel')))),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: FilledButton.icon(
              onPressed: _saveEdit,
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr(context, 'cust_save')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            )),
          ]),
      ]),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final Customer customer;
  const _StatsRow({required this.customer});
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: _StatTile(label: tr(context, 'cust_total_invoices'), value: '${customer.totalInvoices}', color: AppColors.primary)),
    const SizedBox(width: AppSpacing.sm),
    Expanded(child: _StatTile(label: tr(context, 'cust_total_spent'), value: '\$${customer.totalSpent.toStringAsFixed(0)}', color: AppColors.success)),
    const SizedBox(width: AppSpacing.sm),
    Expanded(child: _StatTile(label: tr(context, 'cust_balance'), value: '\$${customer.balance.toStringAsFixed(0)}', color: customer.balance > 0 ? AppColors.error : AppColors.success)),
  ]);
}

class _StatTile extends StatelessWidget {
  final String label; final String value; final Color color;
  const _StatTile({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.12))),
    child: Column(children: [
      Text(value, style: AppTypography.headingSmall.copyWith(color: color)),
      Text(label, style: AppTypography.caption),
    ]),
  );
}

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: AppTypography.labelLarge),
    const SizedBox(height: AppSpacing.md),
    ...children,
  ]);
}

class _InfoRow extends StatelessWidget {
  final IconData icon; final String label; final String value;
  const _InfoRow({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(children: [
      Icon(icon, size: 16, color: AppColors.neutral400),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(width: 100, child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary))),
      Expanded(child: Text(value, style: AppTypography.bodyMedium)),
    ]),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 16, color: color), label: Text(label),
    onPressed: onTap, side: BorderSide(color: color.withValues(alpha: 0.3)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    labelStyle: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500));
}

class _EditField extends StatelessWidget {
  final TextEditingController c; final String label; final TextInputType? keyboard;
  const _EditField({required this.c, required this.label, this.keyboard});
  @override
  Widget build(BuildContext context) => TextField(
    controller: c, keyboardType: keyboard,
    decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
  );
}
