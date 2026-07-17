// SmartBiz AI — Platform Dashboard screen (Step 58.1).
// Real data from GET /api/platform/dashboard. Polished design.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../platform_state.dart';
import '../../../core/api/platform_models.dart';

class PlatformDashboardScreen extends StatefulWidget {
  const PlatformDashboardScreen({super.key});

  @override
  State<PlatformDashboardScreen> createState() => _PlatformDashboardScreenState();
}

class _PlatformDashboardScreenState extends State<PlatformDashboardScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      context.read<PlatformState>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);
    final state = context.watch<PlatformState>();
    final dash = state.dashboard;

    if (state.dashboardLoading && dash == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.dashboardError != null && dash == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.warning),
        const SizedBox(height: 12),
        Text(tr(context, 'plt_load_failed'), style: AppTypography.bodyMedium),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => state.loadDashboard(), child: Text(tr(context, 'gen_retry'))),
      ]));
    }
    if (dash == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () => state.loadDashboard(),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(context, 'sa_dash_title'), style: AppTypography.headingLarge),
                    const SizedBox(height: 4),
                    Text(tr(context, 'sa_dash_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(tr(context, 'sa_all_systems_ok'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
                    ]),
                  ),
                ]),
                const SizedBox(height: AppSpacing.xl),

                // ── KPI Cards ──────────────────────────────
                LayoutBuilder(builder: (_, constraints) {
                  final cols = constraints.maxWidth > 700 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: cols,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: isMobile ? 1.45 : 1.65,
                    children: [
                      _KpiCard(icon: Icons.business, label: tr(context, 'plt_workspaces'),
                        value: '${dash.workspaces.total}', color: AppColors.primary),
                      _KpiCard(icon: Icons.check_circle_outline, label: tr(context, 'plt_active'),
                        value: '${dash.workspaces.active}', color: AppColors.success),
                      _KpiCard(icon: Icons.hourglass_top, label: tr(context, 'plt_trial'),
                        value: '${dash.workspaces.trial}', color: AppColors.warning),
                      _KpiCard(icon: Icons.pause_circle_outline, label: tr(context, 'plt_suspended'),
                        value: '${dash.workspaces.suspended}', color: AppColors.error),
                      _KpiCard(icon: Icons.people, label: tr(context, 'plt_users'),
                        value: '${dash.users.total}', color: AppColors.info),
                      _KpiCard(icon: Icons.campaign, label: tr(context, 'plt_campaigns'),
                        value: '${dash.campaigns.total}', color: AppColors.accent),
                      _KpiCard(icon: Icons.qr_code, label: tr(context, 'plt_codes_unused'),
                        value: '${dash.codes.unused}', color: AppColors.success),
                      _KpiCard(icon: Icons.qr_code_2, label: tr(context, 'plt_codes_used'),
                        value: '${dash.codes.used}', color: AppColors.warning),
                    ],
                  );
                }),
                const SizedBox(height: AppSpacing.xl),

                // ── Main content ───────────────────────────
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: Column(children: [
                        _buildQuickActions(context),
                        const SizedBox(height: AppSpacing.lg),
                        _buildRecentWorkspaces(context, dash),
                      ])),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(flex: 2, child: Column(children: [
                        _buildCodeBreakdown(context, dash),
                        const SizedBox(height: AppSpacing.lg),
                        _buildRecentCodes(context, dash),
                      ])),
                    ],
                  )
                else ...[
                  _buildQuickActions(context),
                  const SizedBox(height: AppSpacing.lg),
                  _buildCodeBreakdown(context, dash),
                  const SizedBox(height: AppSpacing.lg),
                  _buildRecentWorkspaces(context, dash),
                  const SizedBox(height: AppSpacing.lg),
                  _buildRecentCodes(context, dash),
                ],

                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return _SectionCard(
      title: tr(context, 'sa_quick_actions'),
      icon: Icons.flash_on_outlined,
      child: LayoutBuilder(builder: (_, constraints) {
        final cols = constraints.maxWidth > 400 ? 2 : 1;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 3.2,
          children: [
            _QuickActionCard(icon: Icons.business, label: tr(context, 'plt_workspaces'),
              color: AppColors.primary, onTap: () => context.go('/platform/workspaces')),
            _QuickActionCard(icon: Icons.campaign, label: tr(context, 'plt_campaigns'),
              color: AppColors.success, onTap: () => context.go('/platform/campaigns')),
            _QuickActionCard(icon: Icons.qr_code_2, label: tr(context, 'plt_codes'),
              color: AppColors.accent, onTap: () => context.go('/platform/codes')),
            _QuickActionCard(icon: Icons.credit_card, label: tr(context, 'plt_print_cards'),
              color: AppColors.warning, onTap: () => context.go('/platform/cards')),
          ],
        );
      }),
    );
  }

  Widget _buildRecentWorkspaces(BuildContext context, PlatformDashboard dash) {
    if (dash.recentWorkspaces.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: tr(context, 'plt_recent_workspaces'),
      icon: Icons.history,
      actionLabel: tr(context, 'sa_view_all'),
      onAction: () => context.go('/platform/workspaces'),
      child: Column(
        children: dash.recentWorkspaces.map((w) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.business, size: 15, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.name, style: AppTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${w.status ?? '—'} · ${w.subscriptionStatus ?? '—'}',
                  style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
            ])),
            Text(w.createdAt?.substring(0, 10) ?? '', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          ]),
        )).toList(),
      ),
    );
  }

  Widget _buildCodeBreakdown(BuildContext context, PlatformDashboard dash) {
    final total = dash.codes.total;
    return _SectionCard(
      title: tr(context, 'plt_codes'),
      icon: Icons.pie_chart_outline,
      child: Column(children: [
        _BreakdownRow(label: tr(context, 'plt_unused'), count: '${dash.codes.unused}',
          pct: total > 0 ? dash.codes.unused / total : 0, color: AppColors.success),
        _BreakdownRow(label: tr(context, 'plt_used'), count: '${dash.codes.used}',
          pct: total > 0 ? dash.codes.used / total : 0, color: AppColors.primary),
        _BreakdownRow(label: tr(context, 'plt_expired'), count: '${dash.codes.expired}',
          pct: total > 0 ? dash.codes.expired / total : 0, color: AppColors.warning),
        _BreakdownRow(label: tr(context, 'plt_disabled'), count: '${dash.codes.disabled}',
          pct: total > 0 ? dash.codes.disabled / total : 0, color: AppColors.error),
        const Divider(height: 20),
        Row(children: [
          Text(tr(context, 'plt_codes'), style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          const Spacer(),
          Text('$total', style: AppTypography.labelLarge),
        ]),
      ]),
    );
  }

  Widget _buildRecentCodes(BuildContext context, PlatformDashboard dash) {
    if (dash.recentCodeUsage.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: tr(context, 'plt_codes_used'),
      icon: Icons.qr_code_2,
      child: Column(
        children: dash.recentCodeUsage.map((c) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.qr_code, size: 15, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600, fontSize: 13)),
              Text(c.campaignName ?? '', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
            ])),
            Text(c.usedAt?.substring(0, 10) ?? '', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          ]),
        )).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Reusable widgets (same design as old SA dashboard)
// ═══════════════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _KpiCard({required this.icon, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 18, color: color),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: AppTypography.headingSmall),
          Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ]),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionCard({required this.title, required this.icon, required this.child, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.base),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTypography.labelLarge)),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
            child: Text(actionLabel!, style: TextStyle(fontSize: 12, color: AppColors.primary)),
          ),
      ]),
      const SizedBox(height: AppSpacing.md),
      child,
    ]),
  );
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(label, style: AppTypography.labelSmall)),
          Icon(Icons.chevron_right, size: 16, color: AppColors.neutral400),
        ]),
      ),
    ),
  );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String count;
  final double pct;
  final Color color;
  const _BreakdownRow({required this.label, required this.count, required this.pct, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(label, style: AppTypography.bodySmall)),
      SizedBox(width: 30, child: Text(count, style: AppTypography.labelSmall, textAlign: TextAlign.end)),
      const SizedBox(width: AppSpacing.sm),
      SizedBox(
        width: 60,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(value: pct, backgroundColor: AppColors.neutral100, color: color, minHeight: 6),
        ),
      ),
    ]),
  );
}
