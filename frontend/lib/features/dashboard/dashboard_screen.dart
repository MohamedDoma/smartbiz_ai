// SmartBiz AI — Owner Dashboard.
// AI-first command center for business owners.
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
import 'widgets/dashboard_widgets.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);
    final appState = context.watch<AppState>();

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 1. Business Health Header ───────────────
                  _BusinessHeader(appState: appState, isMobile: isMobile),
                  const SizedBox(height: AppSpacing.lg),

                  // ── 2. AI Summary Card ─────────────────────
                  _AiSummaryCard(),
                  const SizedBox(height: AppSpacing.lg),

                  // ── 3. Key Metrics ─────────────────────────
                  DashboardSectionHeader(icon: Icons.analytics_outlined, title: tr(context, 'dash_section_metrics')),
                  const SizedBox(height: AppSpacing.md),
                  _MetricsGrid(isMobile: isMobile, isDesktop: isDesktop),
                  const SizedBox(height: AppSpacing.xl),

                  // Two-column layout on desktop: recommendations + sidebar
                  if (isDesktop)
                    _DesktopTwoColumn()
                  else ...[
                    // ── 4. AI Recommendations ──────────────────
                    DashboardSectionHeader(
                      icon: Icons.auto_awesome,
                      title: tr(context, 'dash_section_recommendations'),
                      trailing: _ViewAllButton(route: '/advisor'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ...MockDashboard.recommendations.map((r) =>
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: RecommendationCardWidget(rec: r),
                        )),
                    const SizedBox(height: AppSpacing.xl),

                    // ── 5. Quick Actions ───────────────────────
                    DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
                    const SizedBox(height: AppSpacing.md),
                    _QuickActionsGrid(isMobile: isMobile),
                    const SizedBox(height: AppSpacing.xl),

                    // ── 6. Operations Snapshot ─────────────────
                    DashboardSectionHeader(icon: Icons.speed, title: tr(context, 'dash_section_ops')),
                    const SizedBox(height: AppSpacing.md),
                    _OpsSnapshotGrid(isMobile: isMobile),
                    const SizedBox(height: AppSpacing.xl),

                    // ── 7. Recent Activity ────────────────────
                    DashboardSectionHeader(icon: Icons.history, title: tr(context, 'dash_section_activity')),
                    const SizedBox(height: AppSpacing.md),
                    _ActivityList(),
                    const SizedBox(height: AppSpacing.xl),

                    // ── 8. System Setup Status ────────────────
                    DashboardSectionHeader(icon: Icons.settings_suggest, title: tr(context, 'dash_section_setup')),
                    const SizedBox(height: AppSpacing.md),
                    _SetupStatusCard(),
                  ],

                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  1. Business Health Header
// ═══════════════════════════════════════════════════════════
class _BusinessHeader extends StatelessWidget {
  final AppState appState;
  final bool isMobile;
  const _BusinessHeader({required this.appState, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'dash_greeting'),
                style: isMobile ? AppTypography.headingMedium : AppTypography.headingLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${appState.currentWorkspace.name}  •  ${appState.currentRole.label(appState.uiLanguage)}',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        // AI status chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(tr(context, 'dash_ai_active'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  2. AI Summary Card
// ═══════════════════════════════════════════════════════════
class _AiSummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.08), AppColors.accent.withValues(alpha: 0.06)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, size: 20, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(context, 'dash_ai_summary_title'), style: AppTypography.labelLarge.copyWith(color: AppColors.accent)),
                const SizedBox(height: AppSpacing.xs),
                Text(tr(context, 'dash_ai_summary_body'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5)),
                const SizedBox(height: AppSpacing.md),
                InkWell(
                  onTap: () => context.go('/ai-chat'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(tr(context, 'dash_ask_ai'), style: AppTypography.labelMedium.copyWith(color: AppColors.accent)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward, size: 14, color: AppColors.accent),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  3. Metrics Grid
// ═══════════════════════════════════════════════════════════
class _MetricsGrid extends StatelessWidget {
  final bool isMobile;
  final bool isDesktop;
  const _MetricsGrid({required this.isMobile, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    final cols = isDesktop ? 3 : (isMobile ? 2 : 3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = isMobile ? AppSpacing.sm : AppSpacing.md;
        final cardWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: MockDashboard.metrics.map((m) => SizedBox(
            width: cardWidth,
            child: MetricCardWidget(metric: m),
          )).toList(),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Quick Actions Grid
// ═══════════════════════════════════════════════════════════
class _QuickActionsGrid extends StatelessWidget {
  final bool isMobile;
  const _QuickActionsGrid({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final cols = isMobile ? 3 : 6;
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppSpacing.sm;
        final cardWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: MockDashboard.quickActions.map((a) => SizedBox(
            width: cardWidth,
            child: QuickActionCardWidget(action: a),
          )).toList(),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Ops Snapshot Grid
// ═══════════════════════════════════════════════════════════
class _OpsSnapshotGrid extends StatelessWidget {
  final bool isMobile;
  const _OpsSnapshotGrid({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final cols = isMobile ? 1 : 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = AppSpacing.sm;
        final cardWidth = cols == 1 ? constraints.maxWidth : (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: MockDashboard.opsSnapshot.map((o) => SizedBox(
            width: cardWidth,
            child: OpsSnapshotCard(item: o),
          )).toList(),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Activity List
// ═══════════════════════════════════════════════════════════
class _ActivityList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: MockDashboard.recentActivity.map((a) => ActivityItemWidget(activity: a)).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Setup Status Card
// ═══════════════════════════════════════════════════════════
class _SetupStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final s = MockDashboard.setupStatus;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SetupRow(icon: Icons.extension, label: tr(context, 'dash_setup_modules'), value: '${s.modulesEnabled} / ${s.totalModules}', good: s.modulesEnabled == s.totalModules),
          _SetupRow(icon: Icons.badge, label: tr(context, 'dash_setup_roles'), value: '${s.rolesConfigured}', good: true),
          _SetupRow(icon: Icons.auto_awesome, label: tr(context, 'dash_setup_ai'), value: tr(context, s.aiAdvisorActive ? 'dash_setup_active' : 'dash_setup_inactive'), good: s.aiAdvisorActive),
          _SetupRow(icon: Icons.credit_card, label: tr(context, 'dash_setup_plan'), value: tr(context, s.planKey), good: true),
        ],
      ),
    );
  }
}

class _SetupRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool good;
  const _SetupRow({required this.icon, required this.label, required this.value, required this.good});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: good ? AppColors.success : AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.bodyMedium)),
          Text(value, style: AppTypography.labelMedium.copyWith(color: good ? AppColors.success : AppColors.warning)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Desktop Two-Column Layout
// ═══════════════════════════════════════════════════════════
class _DesktopTwoColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Recommendations + Activity
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardSectionHeader(
                icon: Icons.auto_awesome,
                title: tr(context, 'dash_section_recommendations'),
                trailing: _ViewAllButton(route: '/advisor'),
              ),
              const SizedBox(height: AppSpacing.md),
              ...MockDashboard.recommendations.map((r) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: RecommendationCardWidget(rec: r),
                  )),
              const SizedBox(height: AppSpacing.xl),

              DashboardSectionHeader(icon: Icons.history, title: tr(context, 'dash_section_activity')),
              const SizedBox(height: AppSpacing.md),
              _ActivityList(),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),

        // Right: Quick Actions + Ops + Setup
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DashboardSectionHeader(icon: Icons.flash_on, title: tr(context, 'dash_section_actions')),
              const SizedBox(height: AppSpacing.md),
              _QuickActionsGrid(isMobile: false),
              const SizedBox(height: AppSpacing.xl),

              DashboardSectionHeader(icon: Icons.speed, title: tr(context, 'dash_section_ops')),
              const SizedBox(height: AppSpacing.md),
              _OpsSnapshotGrid(isMobile: true), // stack in sidebar
              const SizedBox(height: AppSpacing.xl),

              DashboardSectionHeader(icon: Icons.settings_suggest, title: tr(context, 'dash_section_setup')),
              const SizedBox(height: AppSpacing.md),
              _SetupStatusCard(),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  View All Button
// ═══════════════════════════════════════════════════════════
class _ViewAllButton extends StatelessWidget {
  final String route;
  const _ViewAllButton({required this.route});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(route),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr(context, 'dash_view_all'), style: AppTypography.labelMedium.copyWith(color: AppColors.accent)),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_forward, size: 14, color: AppColors.accent),
        ],
      ),
    );
  }
}
