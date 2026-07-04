// SmartBiz AI — Dynamic Dashboard Widget Factory (Phase 16.3).
//
// Converts DashboardWidgetConfig into Flutter widgets.
// Stateless, no Provider, no permission logic.
// Reuses existing dashboard_widgets.dart components where possible.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/dashboard_config_models.dart';
import '../models/dashboard_models.dart';
import 'dashboard_widgets.dart';

// ═══════════════════════════════════════════════════════════
//  Public API
// ═══════════════════════════════════════════════════════════

class DynamicDashboardWidgetFactory {
  DynamicDashboardWidgetFactory._();

  /// Builds the correct widget for a given config.
  static Widget build({
    required BuildContext context,
    required DashboardWidgetConfig config,
  }) {
    return switch (config.type) {
      DashWidgetType.metric          => _buildMetric(context, config),
      DashWidgetType.aiInsight       => _buildAiInsight(context, config),
      DashWidgetType.recentActivity  => _buildListCard(context, config, Icons.history, 'dw_recent_activity'),
      DashWidgetType.taskList        => _buildListCard(context, config, Icons.task_alt, 'dw_tasks'),
      DashWidgetType.approvalQueue   => _buildListCard(context, config, Icons.approval, 'dw_approvals'),
      DashWidgetType.alerts          => _buildAlerts(context, config),
      DashWidgetType.recommendations => _buildListCard(context, config, Icons.auto_awesome, 'dw_recommendations'),
      DashWidgetType.announcements   => _buildAnnouncements(context, config),
      DashWidgetType.setupStatus     => _buildSetupStatus(context, config),
      DashWidgetType.operationsStatus => _buildSummaryCard(context, config, Icons.speed, AppColors.warning),
      DashWidgetType.financeSummary  => _buildSummaryCard(context, config, Icons.account_balance, AppColors.primary),
      DashWidgetType.inventorySummary => _buildSummaryCard(context, config, Icons.warehouse, AppColors.warning),
      DashWidgetType.customerSummary => _buildSummaryCard(context, config, Icons.people, AppColors.info),
      DashWidgetType.employeeSummary => _buildSummaryCard(context, config, Icons.badge, AppColors.info),
      DashWidgetType.hrSummary       => _buildSummaryCard(context, config, Icons.badge, AppColors.info),
      DashWidgetType.projectSummary  => _buildSummaryCard(context, config, Icons.folder, AppColors.accent),
      DashWidgetType.supportQueue    => _buildSummaryCard(context, config, Icons.support_agent, AppColors.info),
      DashWidgetType.serviceSchedule => _buildSummaryCard(context, config, Icons.calendar_today, AppColors.success),
      DashWidgetType.chartPlaceholder => _buildChartPlaceholder(context, config),
      DashWidgetType.moduleSummary   => _buildSummaryCard(context, config, Icons.extension, AppColors.accent),
      DashWidgetType.quickActions    => const SizedBox.shrink(), // handled separately
    };
  }
}

// ═══════════════════════════════════════════════════════════
//  Metric Card — reuses existing MetricCardWidget via adapter
// ═══════════════════════════════════════════════════════════

Widget _buildMetric(BuildContext context, DashboardWidgetConfig config) {
  final meta = config.metadata;
  final metric = DashboardMetric(
    id: config.id,
    labelKey: config.titleKey,
    value: (meta['value'] as String?) ?? '--',
    trend: meta['trend'] as String?,
    trendUp: (meta['trendUp'] as bool?) ?? true,
    iconName: (meta['iconName'] as String?) ?? 'circle',
    colorName: (meta['colorName'] as String?) ?? 'primary',
  );
  return MetricCardWidget(metric: metric);
}

// ═══════════════════════════════════════════════════════════
//  AI Insight Card
// ═══════════════════════════════════════════════════════════

Widget _buildAiInsight(BuildContext context, DashboardWidgetConfig config) {
  final colorName = (config.metadata['colorName'] as String?) ?? 'accent';
  final color = mapColor(colorName);
  final bodyKey = '${config.titleKey}_body';
  return Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.03)],
        begin: AlignmentDirectional.topStart,
        end: AlignmentDirectional.bottomEnd,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, AppColors.primary]),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
      ),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, config.titleKey), style: AppTypography.labelLarge.copyWith(color: color)),
        const SizedBox(height: AppSpacing.xs),
        Text(tr(context, bodyKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: AppSpacing.md),
        InkWell(
          onTap: () => context.go('/ai-chat'),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(tr(context, 'dash_ask_ai'), style: AppTypography.labelMedium.copyWith(color: color)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_forward, size: 14, color: color),
          ]),
        ),
      ])),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Alerts Card
// ═══════════════════════════════════════════════════════════

Widget _buildAlerts(BuildContext context, DashboardWidgetConfig config) {
  return _DynCard(
    icon: Icons.warning_amber,
    iconColor: AppColors.warning,
    title: tr(context, config.titleKey),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _MockRow(icon: Icons.inventory_2, text: tr(context, 'dw_alert_low_stock'), color: AppColors.error),
      _MockRow(icon: Icons.receipt_long, text: tr(context, 'dw_alert_overdue'), color: AppColors.warning),
      _MockRow(icon: Icons.task_alt, text: tr(context, 'dw_alert_pending'), color: AppColors.info),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Announcements Card
// ═══════════════════════════════════════════════════════════

Widget _buildAnnouncements(BuildContext context, DashboardWidgetConfig config) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(
      color: AppColors.info.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.info.withValues(alpha: 0.12)),
    ),
    child: Row(children: [
      const Icon(Icons.campaign, size: 20, color: AppColors.info),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, config.titleKey), style: AppTypography.labelLarge.copyWith(color: AppColors.info)),
        const SizedBox(height: 4),
        Text(tr(context, 'dw_no_announcements'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
      ])),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Setup Status Card
// ═══════════════════════════════════════════════════════════

Widget _buildSetupStatus(BuildContext context, DashboardWidgetConfig config) {
  return _DynCard(
    icon: Icons.settings_suggest,
    iconColor: AppColors.accent,
    title: tr(context, config.titleKey),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _SetupItem(icon: Icons.extension, label: tr(context, 'dash_setup_modules'), value: '5 / 7', good: false),
      _SetupItem(icon: Icons.badge, label: tr(context, 'dash_setup_roles'), value: '4', good: true),
      _SetupItem(icon: Icons.auto_awesome, label: tr(context, 'dash_setup_ai'), value: tr(context, 'dash_setup_active'), good: true),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Generic Summary Card
// ═══════════════════════════════════════════════════════════

Widget _buildSummaryCard(BuildContext context, DashboardWidgetConfig config, IconData icon, Color color) {
  return _DynCard(
    icon: icon,
    iconColor: color,
    title: tr(context, config.titleKey),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _MockRow(icon: Icons.check_circle_outline, text: tr(context, '${config.titleKey}_row1'), color: AppColors.success),
      _MockRow(icon: Icons.pending_outlined, text: tr(context, '${config.titleKey}_row2'), color: AppColors.warning),
      _MockRow(icon: Icons.info_outline, text: tr(context, '${config.titleKey}_row3'), color: AppColors.info),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  List Card (activity, tasks, approvals, recommendations)
// ═══════════════════════════════════════════════════════════

Widget _buildListCard(BuildContext context, DashboardWidgetConfig config, IconData icon, String fallbackKey) {
  return _DynCard(
    icon: icon,
    iconColor: AppColors.accent,
    title: tr(context, config.titleKey),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _MockRow(icon: Icons.circle, text: tr(context, '${config.titleKey}_item1'), color: AppColors.primary, small: true),
      _MockRow(icon: Icons.circle, text: tr(context, '${config.titleKey}_item2'), color: AppColors.success, small: true),
      _MockRow(icon: Icons.circle, text: tr(context, '${config.titleKey}_item3'), color: AppColors.info, small: true),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Chart Placeholder
// ═══════════════════════════════════════════════════════════

Widget _buildChartPlaceholder(BuildContext context, DashboardWidgetConfig config) {
  return _DynCard(
    icon: Icons.bar_chart,
    iconColor: AppColors.accent,
    title: tr(context, config.titleKey),
    child: SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(7, (i) {
          final h = 20.0 + (i * 8.0) % 60;
          return Container(width: 12, height: h, decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.3 + (i * 0.1)),
            borderRadius: BorderRadius.circular(3),
          ));
        }),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Shared helper widgets (private)
// ═══════════════════════════════════════════════════════════

class _DynCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  const _DynCard({required this.icon, required this.iconColor, required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTypography.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: AppSpacing.md),
      child,
    ]),
  );
}

class _MockRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool small;
  const _MockRow({required this.icon, required this.text, required this.color, this.small = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, size: small ? 6 : 14, color: color),
      SizedBox(width: small ? 8 : AppSpacing.sm),
      Expanded(child: Text(text, style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );
}

class _SetupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool good;
  const _SetupItem({required this.icon, required this.label, required this.value, required this.good});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, size: 16, color: good ? AppColors.success : AppColors.warning),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(label, style: AppTypography.bodyMedium)),
      Text(value, style: AppTypography.labelMedium.copyWith(color: good ? AppColors.success : AppColors.warning)),
    ]),
  );
}
