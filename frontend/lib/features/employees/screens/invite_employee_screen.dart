// SmartBiz AI — Invite employee screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../employees_state.dart';
import '../models/employee_models.dart';

class InviteEmployeeScreen extends StatefulWidget {
  const InviteEmployeeScreen({super.key});
  @override
  State<InviteEmployeeScreen> createState() => _InviteEmployeeScreenState();
}

class _InviteEmployeeScreenState extends State<InviteEmployeeScreen> {
  final _nameC = TextEditingController();
  final _emailC = TextEditingController();
  final _phoneC = TextEditingController();
  final _deptC = TextEditingController();
  AppRole _role = AppRole.employee;
  AiAccess _aiAccess = AiAccess.limited;
  String _lang = 'en';

  @override
  void dispose() { _nameC.dispose(); _emailC.dispose(); _phoneC.dispose(); _deptC.dispose(); super.dispose(); }

  void _send() {
    if (_nameC.text.trim().isEmpty || _emailC.text.trim().isEmpty) return;
    context.read<EmployeesState>().inviteEmployee(
      name: _nameC.text.trim(), email: _emailC.text.trim(),
      phone: _phoneC.text.trim().isNotEmpty ? _phoneC.text.trim() : null,
      role: _role, department: _deptC.text.trim().isNotEmpty ? _deptC.text.trim() : null,
      aiAccess: _aiAccess, langPref: _lang,
    );
    context.go('/employees');
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconButton(onPressed: () => context.go('/employees'), icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(tr(context, 'emp_invite_title'), style: AppTypography.headingLarge)),
            ]),
            const SizedBox(height: AppSpacing.xl),

            _Field(controller: _nameC, label: tr(context, 'emp_name'), context: context),
            const SizedBox(height: AppSpacing.md),
            _Field(controller: _emailC, label: tr(context, 'emp_email'), context: context),
            const SizedBox(height: AppSpacing.md),
            _Field(controller: _phoneC, label: tr(context, 'emp_phone'), context: context),
            const SizedBox(height: AppSpacing.md),
            _Field(controller: _deptC, label: tr(context, 'emp_department'), context: context),
            const SizedBox(height: AppSpacing.xl),

            // Role
            Text(tr(context, 'emp_role'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Dropdown<AppRole>(
              value: _role,
              items: AppRole.values.where((r) => r != AppRole.owner).map((r) {
                final key = switch (r) { AppRole.owner => 'role_owner', AppRole.cashier => 'role_cashier', AppRole.warehouse => 'role_warehouse', AppRole.accountant => 'role_accountant', AppRole.employee => 'role_employee' };
                return DropdownMenuItem(value: r, child: Text(tr(context, key)));
              }).toList(),
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: AppSpacing.lg),

            // AI access
            Text(tr(context, 'emp_ai_access'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Dropdown<AiAccess>(
              value: _aiAccess,
              items: AiAccess.values.map((a) {
                final key = switch (a) { AiAccess.full => 'ai_full', AiAccess.limited => 'ai_limited', AiAccess.none => 'ai_none' };
                return DropdownMenuItem(value: a, child: Text(tr(context, key)));
              }).toList(),
              onChanged: (v) => setState(() => _aiAccess = v ?? _aiAccess),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Language
            Text(tr(context, 'emp_lang_pref'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Dropdown<String>(
              value: _lang,
              items: [
                DropdownMenuItem(value: 'en', child: Text(tr(context, 'lang_en'))),
                DropdownMenuItem(value: 'ar', child: Text(tr(context, 'lang_ar'))),
              ],
              onChanged: (v) => setState(() => _lang = v ?? _lang),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 16, color: AppColors.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, 'emp_lang_note'), style: AppTypography.caption.copyWith(color: AppColors.info))),
              ]),
            ),
            const SizedBox(height: AppSpacing.xxl),

            // Actions
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => context.go('/employees'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text(tr(context, 'inv_cancel')),
              )),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: 2, child: FilledButton.icon(
                onPressed: _send,
                icon: const Icon(Icons.send, size: 18),
                label: Text(tr(context, 'emp_send_invite')),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              )),
            ]),
            const SizedBox(height: AppSpacing.xxl),
          ]),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller; final String label; final BuildContext context;
  const _Field({required this.controller, required this.label, required this.context});
  @override
  Widget build(BuildContext _) => TextField(
    controller: controller, textDirection: Directionality.of(context),
    decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
  );
}

class _Dropdown<T> extends StatelessWidget {
  final T value; final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const _Dropdown({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    decoration: BoxDecoration(border: Border.all(color: AppColors.neutral300), borderRadius: BorderRadius.circular(10)),
    child: DropdownButtonHideUnderline(child: DropdownButton<T>(value: value, isExpanded: true, items: items, onChanged: onChanged)),
  );
}
