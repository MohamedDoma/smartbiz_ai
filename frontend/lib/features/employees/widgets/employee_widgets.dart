// SmartBiz AI — Employee shared widgets (backend role/status aware).
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';

class DynamicRoleBadge extends StatelessWidget {
  final String label;
  final bool primary;

  const DynamicRoleBadge({
    super.key,
    required this.label,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: primary ? AppColors.primarySurface : AppColors.neutral100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primary ? AppColors.primary : AppColors.neutral300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: primary ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      );
}

class EmployeeStatusBadge extends StatelessWidget {
  final String status;

  const EmployeeStatusBadge({super.key, required this.status});

  Color get _color => switch (status) {
        'active' => AppColors.success,
        'suspended' => AppColors.error,
        'pending' => AppColors.warning,
        _ => AppColors.neutral500,
      };

  String _label(BuildContext context) => switch (status) {
        'active' => tr(context, 'emp_status_active'),
        'suspended' => tr(context, 'emp_status_suspended'),
        'pending' => tr(context, 'emp_invite_status_pending'),
        _ => status,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _label(context),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _color,
          ),
        ),
      );
}
