// SmartBiz AI — Role-aware Dashboard.
// Delegates to role-specific layouts while reusing shared widgets.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/responsive.dart';
import 'data/mock_dashboard.dart';
import 'data/role_dashboards.dart';
import 'models/dashboard_models.dart';
import 'widgets/dashboard_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return switch (appState.currentRole) {
      AppRole.owner || AppRole.superAdmin => const _OwnerDashboard(),
      AppRole.cashier => const _CashierDashboard(),
      AppRole.warehouse => const _WarehouseDashboard(),
      AppRole.accountant => const _AccountantDashboard(),
      AppRole.employee => const _EmployeeDashboard(),
    };
  }
}

// ═══════════════════════════════════════════════════════════
//  Shared helpers
// ═══════════════════════════════════════════════════════════
class _DashScaffold extends StatelessWidget {
  final String greetingKey;
  final String subtitleKey;
  final IconData roleIcon;
  final Color roleColor;
  final List<Widget> children;
  const _DashScaffold({required this.greetingKey, required this.subtitleKey, required this.roleIcon, required this.roleColor, required this.children});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final appState = context.watch<AppState>();
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Role header
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, greetingKey), style: isMobile ? AppTypography.headingMedium : AppTypography.headingLarge),
              const SizedBox(height: AppSpacing.xs),
              Text('${appState.currentWorkspace.name}  •  ${appState.currentRole.label(appState.uiLanguage)}', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: roleColor.withValues(alpha: 0.3))),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(roleIcon, size: 14, color: roleColor),
                const SizedBox(width: 4),
                Text(tr(context, subtitleKey), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: roleColor)),
              ]),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          ...children,
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _MetricsWrap extends StatelessWidget {
  final List<DashboardMetric> metrics;
  const _MetricsWrap({required this.metrics});
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final cols = isMobile ? 2 : metrics.length.clamp(2, 4);
    return LayoutBuilder(builder: (ctx, c) {
      final spacing = isMobile ? AppSpacing.sm : AppSpacing.md;
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing, children: metrics.map((m) => SizedBox(width: w, child: MetricCardWidget(metric: m))).toList());
    });
  }
}

class _QuickActionsWrap extends StatelessWidget {
  final List<DashboardQuickAction> actions;
  const _QuickActionsWrap({required this.actions});
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final cols = isMobile ? 3 : actions.length.clamp(3, 6);
    return LayoutBuilder(builder: (ctx, c) {
      final spacing = AppSpacing.sm;
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing, children: actions.map((a) => SizedBox(width: w, child: QuickActionCardWidget(action: a))).toList());
    });
  }
}

class _ActivityCard extends StatelessWidget {
  final List<DashboardActivity> activities;
  const _ActivityCard({required this.activities});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
    child: Column(mainAxisSize: MainAxisSize.min, children: activities.map((a) => ActivityItemWidget(activity: a)).toList()),
  );
}

class _AiInsightCard extends StatelessWidget {
  final String titleKey;
  final String bodyKey;
  final IconData icon;
  final Color color;
  const _AiInsightCard({required this.titleKey, required this.bodyKey, this.icon = Icons.auto_awesome, this.color = AppColors.accent});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [color.withValues(alpha: 0.08), color.withValues(alpha: 0.03)], begin: AlignmentDirectional.topStart, end: AlignmentDirectional.bottomEnd),
      borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.15)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(gradient: LinearGradient(colors: [color, AppColors.primary]), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 18, color: Colors.white)),
      const SizedBox(width: AppSpacing.md),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, titleKey), style: AppTypography.labelLarge.copyWith(color: color)),
        const SizedBox(height: AppSpacing.xs),
        Text(tr(context, bodyKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.5)),
        const SizedBox(height: AppSpacing.md),
        InkWell(onTap: () => context.go('/ai-chat'), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(context, 'dash_ask_ai'), style: AppTypography.labelMedium.copyWith(color: color)),
          const SizedBox(width: 4), Icon(Icons.arrow_forward, size: 14, color: color),
        ])),
      ])),
    ]),
  );
}

class _ViewAllButton extends StatelessWidget {
  final String route;
  const _ViewAllButton({required this.route});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.go(route),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(tr(context, 'dash_view_all'), style: AppTypography.labelMedium.copyWith(color: AppColors.accent)),
      const SizedBox(width: 2), const Icon(Icons.arrow_forward, size: 14, color: AppColors.accent),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  1. OWNER / SUPER ADMIN — Full executive overview
// ═══════════════════════════════════════════════════════════
class _OwnerDashboard extends StatelessWidget {
  const _OwnerDashboard();
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);
    return _DashScaffold(
      greetingKey: 'dash_greeting', subtitleKey: 'rd_role_executive', roleIcon: Icons.shield, roleColor: AppColors.primary,
      children: [
        _AiInsightCard(titleKey: 'dash_ai_summary_title', bodyKey: 'dash_ai_summary_body'),
        const SizedBox(height: AppSpacing.lg),
        DashboardSectionHeader(icon: Icons.analytics_outlined, title: tr(context, 'dash_section_metrics')),
        const SizedBox(height: AppSpacing.md),
        _MetricsWrap(metrics: MockDashboard.metrics),
        const SizedBox(height: AppSpacing.xl),
        if (isDesktop) _OwnerDesktopTwoCol() else ...[
          DashboardSectionHeader(icon: Icons.auto_awesome, title: tr(context, 'dash_section_recommendations'), trailing: _ViewAllButton(route: '/advisor')),
          const SizedBox(height: AppSpacing.md),
          ...MockDashboard.recommendations.map((r) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: RecommendationCardWidget(rec: r))),
          const SizedBox(height: AppSpacing.xl),
          DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
          const SizedBox(height: AppSpacing.md),
          _QuickActionsWrap(actions: MockDashboard.quickActions),
          const SizedBox(height: AppSpacing.xl),
          DashboardSectionHeader(icon: Icons.speed, title: tr(context, 'dash_section_ops')),
          const SizedBox(height: AppSpacing.md),
          _OpsGrid(isMobile: isMobile),
          const SizedBox(height: AppSpacing.xl),
          DashboardSectionHeader(icon: Icons.history, title: tr(context, 'dash_section_activity')),
          const SizedBox(height: AppSpacing.md),
          _ActivityCard(activities: MockDashboard.recentActivity),
          const SizedBox(height: AppSpacing.xl),
          DashboardSectionHeader(icon: Icons.settings_suggest, title: tr(context, 'dash_section_setup')),
          const SizedBox(height: AppSpacing.md),
          _SetupStatusCard(),
        ],
      ],
    );
  }
}

class _OwnerDesktopTwoCol extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DashboardSectionHeader(icon: Icons.auto_awesome, title: tr(context, 'dash_section_recommendations'), trailing: _ViewAllButton(route: '/advisor')),
      const SizedBox(height: AppSpacing.md),
      ...MockDashboard.recommendations.map((r) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: RecommendationCardWidget(rec: r))),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.history, title: tr(context, 'dash_section_activity')),
      const SizedBox(height: AppSpacing.md),
      _ActivityCard(activities: MockDashboard.recentActivity),
    ])),
    const SizedBox(width: AppSpacing.lg),
    Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
      const SizedBox(height: AppSpacing.md),
      _QuickActionsWrap(actions: MockDashboard.quickActions),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.speed, title: tr(context, 'dash_section_ops')),
      const SizedBox(height: AppSpacing.md),
      _OpsGrid(isMobile: true),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.settings_suggest, title: tr(context, 'dash_section_setup')),
      const SizedBox(height: AppSpacing.md),
      _SetupStatusCard(),
    ])),
  ]);
}

// ═══════════════════════════════════════════════════════════
//  2. CASHIER — Sales focused
// ═══════════════════════════════════════════════════════════
class _CashierDashboard extends StatelessWidget {
  const _CashierDashboard();
  @override
  Widget build(BuildContext context) => _DashScaffold(
    greetingKey: 'rd_cashier_greeting', subtitleKey: 'rd_role_sales', roleIcon: Icons.point_of_sale, roleColor: AppColors.success,
    children: [
      _AiInsightCard(titleKey: 'rd_cashier_ai_title', bodyKey: 'rd_cashier_ai_body', color: AppColors.success, icon: Icons.point_of_sale),
      const SizedBox(height: AppSpacing.lg),
      DashboardSectionHeader(icon: Icons.analytics_outlined, title: tr(context, 'rd_today_overview')),
      const SizedBox(height: AppSpacing.md),
      _MetricsWrap(metrics: CashierDashboard.metrics),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
      const SizedBox(height: AppSpacing.md),
      _QuickActionsWrap(actions: CashierDashboard.quickActions),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.history, title: tr(context, 'rd_recent_sales')),
      const SizedBox(height: AppSpacing.md),
      _ActivityCard(activities: CashierDashboard.recentActivity),
    ],
  );
}

// ═══════════════════════════════════════════════════════════
//  3. WAREHOUSE — Inventory focused
// ═══════════════════════════════════════════════════════════
class _WarehouseDashboard extends StatelessWidget {
  const _WarehouseDashboard();
  @override
  Widget build(BuildContext context) => _DashScaffold(
    greetingKey: 'rd_warehouse_greeting', subtitleKey: 'rd_role_inventory', roleIcon: Icons.warehouse, roleColor: AppColors.warning,
    children: [
      _AiInsightCard(titleKey: 'rd_warehouse_ai_title', bodyKey: 'rd_warehouse_ai_body', color: AppColors.warning, icon: Icons.warehouse),
      const SizedBox(height: AppSpacing.lg),
      DashboardSectionHeader(icon: Icons.analytics_outlined, title: tr(context, 'rd_stock_overview')),
      const SizedBox(height: AppSpacing.md),
      _MetricsWrap(metrics: WarehouseDashboard.metrics),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
      const SizedBox(height: AppSpacing.md),
      _QuickActionsWrap(actions: WarehouseDashboard.quickActions),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.history, title: tr(context, 'rd_recent_movements')),
      const SizedBox(height: AppSpacing.md),
      _ActivityCard(activities: WarehouseDashboard.recentActivity),
    ],
  );
}

// ═══════════════════════════════════════════════════════════
//  4. ACCOUNTANT — Finance focused
// ═══════════════════════════════════════════════════════════
class _AccountantDashboard extends StatelessWidget {
  const _AccountantDashboard();
  @override
  Widget build(BuildContext context) => _DashScaffold(
    greetingKey: 'rd_accountant_greeting', subtitleKey: 'rd_role_finance', roleIcon: Icons.account_balance, roleColor: AppColors.primary,
    children: [
      _AiInsightCard(titleKey: 'rd_accountant_ai_title', bodyKey: 'rd_accountant_ai_body', color: AppColors.primary, icon: Icons.account_balance),
      const SizedBox(height: AppSpacing.lg),
      DashboardSectionHeader(icon: Icons.analytics_outlined, title: tr(context, 'rd_financial_overview')),
      const SizedBox(height: AppSpacing.md),
      _MetricsWrap(metrics: AccountantDashboard.metrics),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
      const SizedBox(height: AppSpacing.md),
      _QuickActionsWrap(actions: AccountantDashboard.quickActions),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.history, title: tr(context, 'rd_recent_transactions')),
      const SizedBox(height: AppSpacing.md),
      _ActivityCard(activities: AccountantDashboard.recentActivity),
    ],
  );
}

// ═══════════════════════════════════════════════════════════
//  5. EMPLOYEE — Minimal
// ═══════════════════════════════════════════════════════════
class _EmployeeDashboard extends StatelessWidget {
  const _EmployeeDashboard();
  @override
  Widget build(BuildContext context) => _DashScaffold(
    greetingKey: 'rd_employee_greeting', subtitleKey: 'rd_role_team', roleIcon: Icons.badge, roleColor: AppColors.info,
    children: [
      _AiInsightCard(titleKey: 'rd_employee_ai_title', bodyKey: 'rd_employee_ai_body', color: AppColors.info, icon: Icons.badge),
      const SizedBox(height: AppSpacing.lg),
      DashboardSectionHeader(icon: Icons.analytics_outlined, title: tr(context, 'rd_my_overview')),
      const SizedBox(height: AppSpacing.md),
      _MetricsWrap(metrics: EmployeeDashboard.metrics),
      const SizedBox(height: AppSpacing.xl),
      // Announcements placeholder
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(color: AppColors.info.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.info.withValues(alpha: 0.12))),
        child: Row(children: [
          const Icon(Icons.campaign, size: 20, color: AppColors.info),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(context, 'rd_announcements'), style: AppTypography.labelLarge.copyWith(color: AppColors.info)),
            const SizedBox(height: 4),
            Text(tr(context, 'rd_no_announcements'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ])),
        ]),
      ),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
      const SizedBox(height: AppSpacing.md),
      _QuickActionsWrap(actions: EmployeeDashboard.quickActions),
      const SizedBox(height: AppSpacing.xl),
      DashboardSectionHeader(icon: Icons.history, title: tr(context, 'dash_section_activity')),
      const SizedBox(height: AppSpacing.md),
      _ActivityCard(activities: EmployeeDashboard.recentActivity),
    ],
  );
}

// ═══════════════════════════════════════════════════════════
//  Shared: OpsGrid + SetupStatus (owner only)
// ═══════════════════════════════════════════════════════════
class _OpsGrid extends StatelessWidget {
  final bool isMobile;
  const _OpsGrid({required this.isMobile});
  @override
  Widget build(BuildContext context) {
    final cols = isMobile ? 1 : 2;
    return LayoutBuilder(builder: (ctx, c) {
      final spacing = AppSpacing.sm;
      final w = cols == 1 ? c.maxWidth : (c.maxWidth - spacing) / 2;
      return Wrap(spacing: spacing, runSpacing: spacing, children: MockDashboard.opsSnapshot.map((o) => SizedBox(width: w, child: OpsSnapshotCard(item: o))).toList());
    });
  }
}

class _SetupStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = MockDashboard.setupStatus;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _SetupRow(icon: Icons.extension, label: tr(context, 'dash_setup_modules'), value: '${s.modulesEnabled} / ${s.totalModules}', good: s.modulesEnabled == s.totalModules),
        _SetupRow(icon: Icons.badge, label: tr(context, 'dash_setup_roles'), value: '${s.rolesConfigured}', good: true),
        _SetupRow(icon: Icons.auto_awesome, label: tr(context, 'dash_setup_ai'), value: tr(context, s.aiAdvisorActive ? 'dash_setup_active' : 'dash_setup_inactive'), good: s.aiAdvisorActive),
        _SetupRow(icon: Icons.credit_card, label: tr(context, 'dash_setup_plan'), value: tr(context, s.planKey), good: true),
      ]),
    );
  }
}

class _SetupRow extends StatelessWidget {
  final IconData icon; final String label; final String value; final bool good;
  const _SetupRow({required this.icon, required this.label, required this.value, required this.good});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
    child: Row(children: [
      Icon(icon, size: 16, color: good ? AppColors.success : AppColors.warning),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(label, style: AppTypography.bodyMedium)),
      Text(value, style: AppTypography.labelMedium.copyWith(color: good ? AppColors.success : AppColors.warning)),
    ]),
  );
}
