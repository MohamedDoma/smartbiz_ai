// SmartBiz AI — Dashboard Preview Widget (Phase 16.3).
//
// Lightweight preview card for the Role Builder / Role Detail screen.
// Shows a structured summary of the resolved dashboard configuration
// without rendering the full production dashboard.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/dashboard_config_models.dart';

class DashboardPreview extends StatelessWidget {
  final DashboardConfiguration configuration;
  final int totalWidgetCount;

  const DashboardPreview({
    super.key,
    required this.configuration,
    this.totalWidgetCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final tpl = configuration.template;
    final visibleWidgets = configuration.widgets.where((w) => w.enabled).toList();
    final hiddenCount = totalWidgetCount > 0
        ? totalWidgetCount - visibleWidgets.length
        : 0;

    final accent = _accentFor(tpl);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ────────────────────────────────────────
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(_iconFor(tpl.iconName), size: 18, color: accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, tpl.labelKey), style: AppTypography.labelLarge.copyWith(color: accent)),
            Text(tr(context, tpl.descriptionKey), style: AppTypography.caption.copyWith(color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
          ])),
          // Source badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primarySurface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr(context, _sourceKey(configuration.source)),
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
            ),
          ),
        ]),
        const Divider(height: AppSpacing.lg),

        // ── Visible Widgets ─────────────────────────────
        Text(tr(context, 'dp_visible_widgets'), style: AppTypography.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        if (visibleWidgets.isEmpty)
          Text(tr(context, 'dp_no_widgets'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary))
        else
          Wrap(spacing: 6, runSpacing: 6, children: visibleWidgets.map((w) => _WidgetChip(
            label: tr(context, w.titleKey),
            icon: _widgetTypeIcon(w.type),
            color: AppColors.success,
          )).toList()),
        const SizedBox(height: AppSpacing.md),

        // ── Hidden Widgets ──────────────────────────────
        if (hiddenCount > 0) ...[
          Row(children: [
            const Icon(Icons.visibility_off, size: 14, color: AppColors.neutral500),
            const SizedBox(width: 4),
            Text(
              '${tr(context, 'dp_hidden_widgets')}: $hiddenCount',
              style: AppTypography.caption.copyWith(color: AppColors.neutral500),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
        ],

        // ── Quick Actions ───────────────────────────────
        Text(tr(context, 'dp_quick_actions'), style: AppTypography.labelMedium),
        const SizedBox(height: AppSpacing.xs),
        if (configuration.quickActions.isEmpty)
          Text(tr(context, 'dp_no_actions'), style: AppTypography.caption.copyWith(color: AppColors.textSecondary))
        else
          Wrap(spacing: 6, runSpacing: 6, children: configuration.quickActions.map((a) => _WidgetChip(
            label: tr(context, a.labelKey),
            icon: _actionIcon(a.iconName),
            color: AppColors.accent,
          )).toList()),
        const SizedBox(height: AppSpacing.md),

        // ── Landing Route ───────────────────────────────
        Row(children: [
          const Icon(Icons.open_in_new, size: 14, color: AppColors.info),
          const SizedBox(width: 4),
          Text(
            '${tr(context, 'dp_landing_route')}: ${configuration.landingRoute}',
            style: AppTypography.caption.copyWith(color: AppColors.info),
          ),
        ]),
      ]),
    );
  }

  static Color _accentFor(DashboardTemplate tpl) => switch (tpl.colorName) {
    'primary' => AppColors.primary,
    'success' => AppColors.success,
    'warning' => AppColors.warning,
    'info' => AppColors.info,
    'accent' => AppColors.accent,
    _ => AppColors.neutral500,
  };

  static String _sourceKey(DashboardSource source) => switch (source) {
    DashboardSource.systemDefault => 'ds_system_default',
    DashboardSource.workspaceRole => 'ds_workspace_role',
    DashboardSource.employeeOverride => 'ds_employee_override',
    DashboardSource.aiGenerated => 'ds_ai_generated',
  };

  static IconData _iconFor(String iconName) => switch (iconName) {
    'shield' => Icons.shield,
    'point_of_sale' => Icons.point_of_sale,
    'account_balance' => Icons.account_balance,
    'warehouse' => Icons.warehouse,
    'badge' => Icons.badge,
    'folder' => Icons.folder,
    'speed' => Icons.speed,
    'support_agent' => Icons.support_agent,
    'build' => Icons.build,
    'person' => Icons.person,
    'dashboard_customize' => Icons.dashboard_customize,
    _ => Icons.dashboard,
  };

  static IconData _widgetTypeIcon(DashWidgetType type) => switch (type) {
    DashWidgetType.metric => Icons.analytics,
    DashWidgetType.aiInsight => Icons.auto_awesome,
    DashWidgetType.quickActions => Icons.flash_on,
    DashWidgetType.alerts => Icons.warning,
    DashWidgetType.recentActivity => Icons.history,
    DashWidgetType.taskList => Icons.checklist,
    DashWidgetType.chartPlaceholder => Icons.bar_chart,
    DashWidgetType.moduleSummary => Icons.summarize,
    DashWidgetType.approvalQueue => Icons.approval,
    DashWidgetType.employeeSummary => Icons.people,
    DashWidgetType.financeSummary => Icons.account_balance_wallet,
    DashWidgetType.inventorySummary => Icons.inventory,
    DashWidgetType.customerSummary => Icons.contacts,
    DashWidgetType.projectSummary => Icons.folder_open,
    DashWidgetType.supportQueue => Icons.support_agent,
    DashWidgetType.hrSummary => Icons.badge,
    DashWidgetType.serviceSchedule => Icons.calendar_today,
    DashWidgetType.operationsStatus => Icons.speed,
    DashWidgetType.announcements => Icons.campaign,
    DashWidgetType.setupStatus => Icons.construction,
    DashWidgetType.recommendations => Icons.lightbulb,
  };

  static IconData _actionIcon(String iconName) => switch (iconName) {
    'add_circle' => Icons.add_circle,
    'receipt_long' => Icons.receipt_long,
    'inventory_2' => Icons.inventory_2,
    'people' => Icons.people,
    'bar_chart' => Icons.bar_chart,
    'auto_awesome' => Icons.auto_awesome,
    'account_balance' => Icons.account_balance,
    'move_to_inbox' => Icons.move_to_inbox,
    'upload' => Icons.upload,
    'approval' => Icons.approval,
    'assignment' => Icons.assignment,
    'support' => Icons.support,
    'build' => Icons.build,
    'schedule' => Icons.schedule,
    'settings' => Icons.settings,
    _ => Icons.flash_on,
  };
}

class _WidgetChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _WidgetChip({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Flexible(child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color), overflow: TextOverflow.ellipsis)),
    ]),
  );
}
