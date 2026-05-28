// SmartBiz AI — Employee shared widgets (badges).
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../models/employee_models.dart';

/// Role badge.
class RoleBadge extends StatelessWidget {
  final AppRole role;
  const RoleBadge({super.key, required this.role});

  Color get _color => switch (role) {
    AppRole.owner => AppColors.primary,
    AppRole.cashier => AppColors.info,
    AppRole.warehouse => AppColors.warning,
    AppRole.accountant => AppColors.success,
    AppRole.employee => AppColors.neutral500,
  };

  String _key() => switch (role) {
    AppRole.owner => 'role_owner',
    AppRole.cashier => 'role_cashier',
    AppRole.warehouse => 'role_warehouse',
    AppRole.accountant => 'role_accountant',
    AppRole.employee => 'role_employee',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(tr(context, _key()), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color)),
    );
  }
}

/// Employee status badge.
class EmpStatusBadge extends StatelessWidget {
  final EmpStatus status;
  const EmpStatusBadge({super.key, required this.status});

  Color get _color => switch (status) {
    EmpStatus.active => AppColors.success,
    EmpStatus.invited => AppColors.info,
    EmpStatus.suspended => AppColors.error,
  };
  String _key() => switch (status) {
    EmpStatus.active => 'emp_status_active',
    EmpStatus.invited => 'emp_status_invited',
    EmpStatus.suspended => 'emp_status_suspended',
  };

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 6, height: 6, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(tr(context, _key()), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _color)),
    ]);
  }
}

/// AI access badge.
class AiAccessBadge extends StatelessWidget {
  final AiAccess access;
  const AiAccessBadge({super.key, required this.access});

  Color get _color => switch (access) {
    AiAccess.full => AppColors.accent,
    AiAccess.limited => AppColors.warning,
    AiAccess.none => AppColors.neutral500,
  };
  IconData get _icon => switch (access) {
    AiAccess.full => Icons.auto_awesome,
    AiAccess.limited => Icons.auto_awesome_outlined,
    AiAccess.none => Icons.block,
  };
  String _key() => switch (access) {
    AiAccess.full => 'ai_full',
    AiAccess.limited => 'ai_limited',
    AiAccess.none => 'ai_none',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_icon, size: 12, color: _color),
        const SizedBox(width: 3),
        Text(tr(context, _key()), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _color)),
      ]),
    );
  }
}
