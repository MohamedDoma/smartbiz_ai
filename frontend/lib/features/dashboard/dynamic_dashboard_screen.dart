// SmartBiz AI — Dynamic Dashboard Screen (Phase 16.3).
//
// Renders a resolved DashboardConfiguration. Does NOT resolve roles,
// permissions, or fetch data. Pure presentation layer.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/responsive.dart';
import 'models/dashboard_config_models.dart';
import 'widgets/dashboard_widgets.dart';
import 'widgets/dynamic_dashboard_widget_factory.dart';
import 'widgets/workspace_setup_status_card.dart';
import 'widgets/workspace_branding_card.dart';

class DynamicDashboardScreen extends StatelessWidget {
  const DynamicDashboardScreen({
    super.key,
    required this.configuration,
    this.workspaceName,
    this.roleName,
  });

  final DashboardConfiguration configuration;
  final String? workspaceName;
  final String? roleName;

  @override
  Widget build(BuildContext context) {
    if (!_hasContent) return _EmptyDashboard(templateKey: configuration.template.labelKey);

    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          sliver: SliverList.list(children: [
            Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Header ──────────────────────────────────
                _DashHeader(
                  templateKey: configuration.template.labelKey,
                  workspaceName: workspaceName,
                  roleName: roleName,
                  source: configuration.source,
                  templateIcon: _templateIcon(configuration.template),
                  templateColor: mapColor(configuration.template.colorName),
                ),
                const SizedBox(height: AppSpacing.md),

                const WorkspaceSetupStatusCard(),
                const SizedBox(height: AppSpacing.sm),

                // ── Workspace Branding ─────────────────────
                WorkspaceBrandingCard(
                  workspaceName: workspaceName,
                  roleName: roleName,
                  template: configuration.template,
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Quick Actions ───────────────────────────
                if (configuration.quickActions.isNotEmpty) ...[
                  DashboardSectionHeader(
                    icon: Icons.flash_on,
                    title: tr(context, 'dash_section_actions'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _QuickActionsSection(actions: configuration.quickActions, isMobile: isMobile),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Widgets ─────────────────────────────────
                if (isDesktop)
                  _DesktopWidgetGrid(widgets: configuration.widgets)
                else
                  _MobileWidgetList(widgets: configuration.widgets),

                const SizedBox(height: AppSpacing.xxl),
              ]),
            )),
          ]),
        ),
      ],
    );
  }

  bool get _hasContent =>
      configuration.widgets.isNotEmpty || configuration.quickActions.isNotEmpty;

  static IconData _templateIcon(DashboardTemplate t) => switch (t) {
    DashboardTemplate.executive => Icons.shield,
    DashboardTemplate.sales => Icons.point_of_sale,
    DashboardTemplate.finance => Icons.account_balance,
    DashboardTemplate.inventory => Icons.warehouse,
    DashboardTemplate.hr => Icons.badge,
    DashboardTemplate.projects => Icons.folder_outlined,
    DashboardTemplate.operations => Icons.speed,
    DashboardTemplate.support => Icons.support_agent,
    DashboardTemplate.service => Icons.build_outlined,
    DashboardTemplate.basicEmployee => Icons.person,
    DashboardTemplate.custom => Icons.dashboard_customize,
  };
}

// ═══════════════════════════════════════════════════════════
//  Header
// ═══════════════════════════════════════════════════════════

class _DashHeader extends StatelessWidget {
  final String templateKey;
  final String? workspaceName;
  final String? roleName;
  final DashboardSource source;
  final IconData templateIcon;
  final Color templateColor;

  const _DashHeader({
    required this.templateKey,
    this.workspaceName,
    this.roleName,
    required this.source,
    required this.templateIcon,
    required this.templateColor,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          tr(context, 'dash_greeting'),
          style: isMobile ? AppTypography.headingMedium : AppTypography.headingLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [if (workspaceName != null) workspaceName!, if (roleName != null) roleName!].join('  •  '),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
      ])),
      _SourceBadge(source: source, icon: templateIcon, color: templateColor, templateKey: templateKey),
    ]);
  }
}

class _SourceBadge extends StatelessWidget {
  final DashboardSource source;
  final IconData icon;
  final Color color;
  final String templateKey;
  const _SourceBadge({required this.source, required this.icon, required this.color, required this.templateKey});

  String get _sourceKey => switch (source) {
    DashboardSource.systemDefault => 'dcfg_source_system',
    DashboardSource.workspaceRole => 'dcfg_source_workspace',
    DashboardSource.employeeOverride => 'dcfg_source_employee',
    DashboardSource.aiGenerated => 'dcfg_source_ai',
  };

  @override
  Widget build(BuildContext context) {
    final label = tr(context, _sourceKey);
    // If l10n key not yet added, show template name
    final displayLabel = label.startsWith('[') ? tr(context, templateKey) : label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(displayLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Quick Actions Section
// ═══════════════════════════════════════════════════════════

class _QuickActionsSection extends StatelessWidget {
  final List<DashboardQuickActionConfig> actions;
  final bool isMobile;
  const _QuickActionsSection({required this.actions, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final cols = isMobile ? 3 : actions.length.clamp(3, 6);
    return LayoutBuilder(builder: (ctx, c) {
      final spacing = AppSpacing.sm;
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: actions.map((a) => SizedBox(
          width: w,
          child: _QuickActionTile(action: a),
        )).toList(),
      );
    });
  }
}

class _QuickActionTile extends StatelessWidget {
  final DashboardQuickActionConfig action;
  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _navigate(context, action.route),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(10)),
            child: Icon(_mapActionIcon(action.iconName), size: 20, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tr(context, action.labelKey),
            style: AppTypography.labelMedium.copyWith(color: AppColors.textPrimary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Desktop Widget Grid (multi-column)
// ═══════════════════════════════════════════════════════════

class _DesktopWidgetGrid extends StatelessWidget {
  final List<DashboardWidgetConfig> widgets;
  const _DesktopWidgetGrid({required this.widgets});

  @override
  Widget build(BuildContext context) {
    // Split: large widgets get full row, small/medium share 2-col rows
    final List<Widget> rows = [];
    int i = 0;
    while (i < widgets.length) {
      final w = widgets[i];
      final built = DynamicDashboardWidgetFactory.build(context: context, config: w);
      if (w.size == WidgetSize.large) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: built,
        ));
        i++;
      } else {
        // Try to pair two small/medium widgets
        if (i + 1 < widgets.length && widgets[i + 1].size != WidgetSize.large) {
          final next = widgets[i + 1];
          final builtNext = DynamicDashboardWidgetFactory.build(context: context, config: next);
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: built),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: builtNext),
            ]),
          ));
          i += 2;
        } else {
          rows.add(Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: built,
          ));
          i++;
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

// ═══════════════════════════════════════════════════════════
//  Mobile Widget List (single column)
// ═══════════════════════════════════════════════════════════

class _MobileWidgetList extends StatelessWidget {
  final List<DashboardWidgetConfig> widgets;
  const _MobileWidgetList({required this.widgets});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final w in widgets)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: DynamicDashboardWidgetFactory.build(context: context, config: w),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Empty State
// ═══════════════════════════════════════════════════════════

class _EmptyDashboard extends StatelessWidget {
  final String templateKey;
  const _EmptyDashboard({required this.templateKey});

  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.dashboard_outlined, size: 32, color: AppColors.info),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          tr(context, 'dyn_dash_empty_title'),
          style: AppTypography.headingSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          tr(context, 'dyn_dash_empty_desc'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: () => context.go('/ai-chat'),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: Text(tr(context, 'dash_action_ai_chat')),
        ),
      ]),
    ));
  }
}

// ═══════════════════════════════════════════════════════════
//  Icon Mapper (private — maps config string → IconData)
// ═══════════════════════════════════════════════════════════

IconData _mapActionIcon(String name) => switch (name) {
  'receipt_long' => Icons.receipt_long,
  'receipt' => Icons.receipt,
  'people' => Icons.people,
  'person_add' => Icons.person_add_outlined,
  'inventory_2' => Icons.inventory_2,
  'warehouse' => Icons.warehouse,
  'add_box' => Icons.add_box_outlined,
  'auto_awesome' => Icons.auto_awesome,
  'bar_chart' => Icons.bar_chart,
  'lightbulb' => Icons.lightbulb_outlined,
  'account_balance' => Icons.account_balance,
  'shield' => Icons.shield_outlined,
  'account_tree' => Icons.account_tree_outlined,
  'settings' => Icons.settings,
  'trending_up' => Icons.trending_up,
  'build' => Icons.build_outlined,
  'support_agent' => Icons.support_agent,
  'folder' => Icons.folder_outlined,
  'task_alt' => Icons.task_alt,
  'calendar_today' => Icons.calendar_today,
  'speed' => Icons.speed,
  'badge' => Icons.badge,
  'dashboard_customize' => Icons.dashboard_customize,
  _ => Icons.circle,
};

void _navigate(BuildContext context, String route) {
  if (route.isEmpty) return;
  try {
    GoRouter.of(context).go(route);
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, 'dyn_dash_invalid_route')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
