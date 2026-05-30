// SmartBiz AI — Invite employee screen (Phase 16.2).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../employees_state.dart';
import '../org_state.dart';
import '../roles_state.dart';
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
  AppRole _role = AppRole.employee;
  AiAccess _aiAccess = AiAccess.limited;
  String _lang = 'en';
  String? _deptId;
  String? _managerId;
  String _primaryRoleId = 'sys_employee';
  final List<String> _extraRoleIds = [];

  @override
  void dispose() { _nameC.dispose(); _emailC.dispose(); _phoneC.dispose(); super.dispose(); }

  void _send() {
    if (_nameC.text.trim().isEmpty || _emailC.text.trim().isEmpty) return;
    final orgState = context.read<OrgState>();
    final dept = _deptId != null ? orgState.getDept(_deptId!)?.name : null;
    context.read<EmployeesState>().inviteEmployee(
      name: _nameC.text.trim(), email: _emailC.text.trim(),
      phone: _phoneC.text.trim().isNotEmpty ? _phoneC.text.trim() : null,
      role: _role, department: dept,
      aiAccess: _aiAccess, langPref: _lang,
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(context, 'asgn_invite_sent')),
      backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
    context.go('/employees');
  }

  @override
  Widget build(BuildContext context) {
    final orgState = context.watch<OrgState>();
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
            const SizedBox(height: AppSpacing.xl),

            // ── Department ──────────────────────────────
            if (orgState.deptsEnabled) ...[
              Text(tr(context, 'org_department'), style: AppTypography.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              _Dropdown<String?>(
                value: _deptId,
                items: [DropdownMenuItem<String?>(value: null, child: Text(tr(context, 'asgn_none'))),
                  ...orgState.departments.map((d) => DropdownMenuItem<String?>(value: d.id, child: Text(d.name)))],
                onChanged: (v) => setState(() => _deptId = v),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Manager ─────────────────────────────────
            Text(tr(context, 'asgn_manager'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Dropdown<String?>(
              value: _managerId,
              items: [DropdownMenuItem<String?>(value: null, child: Text(tr(context, 'asgn_none'))),
                ...orgState.allEmployeeIds.map((id) => DropdownMenuItem<String?>(value: id, child: Text(orgState.empName(id))))],
              onChanged: (v) => setState(() => _managerId = v),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Primary Role ────────────────────────────
            Text(tr(context, 'asgn_primary_role'), style: AppTypography.labelLarge),
            const SizedBox(height: AppSpacing.sm),
            _Dropdown<String>(
              value: _primaryRoleId,
              items: RoleTemplates.allSelectableRoles().where((r) => r.id != 'sys_owner').map((r) =>
                DropdownMenuItem(value: r.id, child: Text(r.name))).toList(),
              onChanged: (v) => setState(() => _primaryRoleId = v ?? _primaryRoleId),
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Extra Roles ─────────────────────────────
            Text(tr(context, 'asgn_extra_roles'), style: AppTypography.labelLarge),
            Text(tr(context, 'asgn_extra_hint'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: 6, runSpacing: 6, children: RoleTemplates.allSelectableRoles()
                .where((r) => r.id != 'sys_owner' && r.id != _primaryRoleId)
                .map((r) {
              final isExtra = _extraRoleIds.contains(r.id);
              return FilterChip(label: Text(r.name), selected: isExtra,
                onSelected: (_) => setState(() { if (isExtra) { _extraRoleIds.remove(r.id); } else { _extraRoleIds.add(r.id); } }),
                selectedColor: AppColors.accent.withValues(alpha: 0.12), checkmarkColor: AppColors.accent,
                side: BorderSide(color: isExtra ? AppColors.accent : AppColors.neutral300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isExtra ? AppColors.accent : AppColors.textSecondary));
            }).toList()),
            const SizedBox(height: AppSpacing.lg),

            // ── System Role (maps to Employee model) ────
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
