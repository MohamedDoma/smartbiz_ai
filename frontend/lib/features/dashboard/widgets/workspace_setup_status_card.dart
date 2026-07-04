// SmartBiz AI — Workspace Setup Status Card.
//
// Lightweight status panel showing the current workspace blueprint state.
// Reads only from existing state providers (WorkspaceModuleState,
// BlueprintNavigationController). No backend calls.
//
// Temporary: displays frontend demo/profile status until AI/backend
// blueprint configuration is connected.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/modules/workspace_module_state.dart';
import '../../../core/modules/blueprint_navigation_controller.dart';
import '../../../core/modules/module_navigation_resolver.dart' as nav_resolver;

class WorkspaceSetupStatusCard extends StatelessWidget {
  const WorkspaceSetupStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final moduleState = context.watch<WorkspaceModuleState>();
    final navCtrl = context.watch<BlueprintNavigationController>();

    final applied = moduleState.blueprintApplied;
    final enabledCount = moduleState.enabledModuleIds.length;
    final mode = navCtrl.mode;

    final statusColor = applied ? AppColors.success : AppColors.warning;
    final statusIcon = applied ? Icons.check_circle_outline : Icons.pending_outlined;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Title row ─────────────────────────────────
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  tr(context, 'ws_setup_title'),
                  style: AppTypography.labelLarge,
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      tr(context, applied ? 'ws_setup_active' : 'ws_setup_pending'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Info chips row ────────────────────────────
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _InfoChip(
                icon: Icons.extension_outlined,
                label: tr(context, 'ws_setup_modules_count')
                    .replaceFirst('{count}', '$enabledCount'),
              ),
              _InfoChip(
                icon: mode == nav_resolver.NavigationMode.advanced
                    ? Icons.rocket_launch_outlined
                    : Icons.bolt_outlined,
                label: tr(
                  context,
                  mode == nav_resolver.NavigationMode.advanced
                      ? 'ws_setup_mode_advanced'
                      : 'ws_setup_mode_basic',
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.sm),

          // ── Pending note ──────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 13,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  tr(context, 'ws_setup_ai_pending'),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Small info chip (internal)
// ─────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
