// SmartBiz AI — Super Admin Dashboard screen.
// Polished platform overview with KPI cards, activity, alerts, quick actions.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';

class SuperAdminDashboardScreen extends StatelessWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isDesktop = Responsive.isDesktop(context);

    return SingleChildScrollView(
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
                final cols = constraints.maxWidth > 700 ? 3 : 2;
                return GridView.count(
                  crossAxisCount: cols,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: isMobile ? 1.45 : 1.65,
                  children: [
                    _KpiCard(icon: Icons.business, label: tr(context, 'sa_total_tenants'),
                      value: '24', delta: '+3', deltaPositive: true, color: AppColors.primary),
                    _KpiCard(icon: Icons.check_circle_outline, label: tr(context, 'sa_active_ws'),
                      value: '18', delta: '+2', deltaPositive: true, color: AppColors.success),
                    _KpiCard(icon: Icons.hourglass_top, label: tr(context, 'sa_trial_accounts'),
                      value: '6', delta: '-1', deltaPositive: false, color: AppColors.warning),
                    _KpiCard(icon: Icons.payments_outlined, label: tr(context, 'sa_mrr'),
                      value: '\$4,280', delta: '+12%', deltaPositive: true, color: AppColors.info),
                    _KpiCard(icon: Icons.auto_awesome, label: tr(context, 'sa_ai_requests'),
                      value: '12,450', delta: '+18%', deltaPositive: true, color: AppColors.accent),
                    _KpiCard(icon: Icons.monitor_heart_outlined, label: tr(context, 'sa_system_status'),
                      value: tr(context, 'sa_status_healthy'), delta: '99.9%', deltaPositive: true, color: AppColors.success),
                  ],
                );
              }),
              const SizedBox(height: AppSpacing.xl),

              // ── Main content: desktop = 2-col, mobile = stacked ──
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Activity + Quick actions
                    Expanded(flex: 3, child: Column(children: [
                      _buildActivitySection(context),
                      const SizedBox(height: AppSpacing.lg),
                      _buildQuickActions(context),
                    ])),
                    const SizedBox(width: AppSpacing.lg),
                    // Right: Alerts + Tenant breakdown
                    Expanded(flex: 2, child: Column(children: [
                      _buildAlertsSection(context),
                      const SizedBox(height: AppSpacing.lg),
                      _buildTenantBreakdown(context),
                    ])),
                  ],
                )
              else ...[
                _buildActivitySection(context),
                const SizedBox(height: AppSpacing.lg),
                _buildAlertsSection(context),
                const SizedBox(height: AppSpacing.lg),
                _buildQuickActions(context),
                const SizedBox(height: AppSpacing.lg),
                _buildTenantBreakdown(context),
              ],

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Platform Activity
  // ═══════════════════════════════════════════════════════════

  Widget _buildActivitySection(BuildContext context) {
    return _SectionCard(
      title: tr(context, 'sa_recent_activity'),
      icon: Icons.history,
      actionLabel: tr(context, 'sa_view_all'),
      onAction: () => context.go('/super-admin/tenants'),
      child: Column(children: [
        _ActivityRow(
          icon: Icons.person_add,
          text: tr(context, 'sa_act_new_tenant'),
          time: tr(context, 'sa_time_2h'),
          color: AppColors.success,
          badge: tr(context, 'sa_badge_new'),
          badgeColor: AppColors.success,
        ),
        _ActivityRow(
          icon: Icons.upgrade,
          text: tr(context, 'sa_act_plan_upgrade'),
          time: tr(context, 'sa_time_5h'),
          color: AppColors.primary,
          badge: tr(context, 'sa_badge_upgrade'),
          badgeColor: AppColors.primary,
        ),
        _ActivityRow(
          icon: Icons.extension,
          text: tr(context, 'sa_act_module_enabled'),
          time: tr(context, 'sa_time_1d'),
          color: AppColors.accent,
        ),
        _ActivityRow(
          icon: Icons.auto_awesome,
          text: tr(context, 'sa_act_ai_spike'),
          time: tr(context, 'sa_time_2d'),
          color: AppColors.warning,
          badge: tr(context, 'sa_badge_alert'),
          badgeColor: AppColors.warning,
        ),
        _ActivityRow(
          icon: Icons.payment,
          text: tr(context, 'sa_act_payment_received'),
          time: tr(context, 'sa_time_2d'),
          color: AppColors.info,
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Alerts
  // ═══════════════════════════════════════════════════════════

  Widget _buildAlertsSection(BuildContext context) {
    return _SectionCard(
      title: tr(context, 'sa_alerts'),
      icon: Icons.notifications_active_outlined,
      child: Column(children: [
        _AlertTile(
          icon: Icons.hourglass_bottom,
          title: tr(context, 'sa_alert_trial'),
          subtitle: tr(context, 'sa_alert_trial_desc'),
          color: AppColors.warning,
          severity: tr(context, 'sa_sev_medium'),
          severityColor: AppColors.warning,
        ),
        _AlertTile(
          icon: Icons.credit_card_off,
          title: tr(context, 'sa_alert_payment'),
          subtitle: tr(context, 'sa_alert_payment_desc'),
          color: AppColors.error,
          severity: tr(context, 'sa_sev_high'),
          severityColor: AppColors.error,
        ),
        _AlertTile(
          icon: Icons.speed,
          title: tr(context, 'sa_alert_ai_limit'),
          subtitle: tr(context, 'sa_alert_ai_limit_desc'),
          color: AppColors.accent,
          severity: tr(context, 'sa_sev_low'),
          severityColor: AppColors.info,
        ),
        _AlertTile(
          icon: Icons.check_circle,
          title: tr(context, 'sa_alert_system_ok'),
          subtitle: tr(context, 'sa_alert_system_ok_desc'),
          color: AppColors.success,
          severity: tr(context, 'sa_sev_ok'),
          severityColor: AppColors.success,
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Quick Actions
  // ═══════════════════════════════════════════════════════════

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
            _QuickActionCard(icon: Icons.business, label: tr(context, 'sa_qa_tenants'),
              color: AppColors.primary, onTap: () => context.go('/super-admin/tenants')),
            _QuickActionCard(icon: Icons.card_membership, label: tr(context, 'sa_qa_plans'),
              color: AppColors.success, onTap: () => context.go('/super-admin/plans')),
            _QuickActionCard(icon: Icons.extension, label: tr(context, 'sa_qa_modules'),
              color: AppColors.accent, onTap: () => context.go('/super-admin/modules')),
            _QuickActionCard(icon: Icons.auto_awesome, label: tr(context, 'sa_qa_usage'),
              color: AppColors.warning, onTap: () => context.go('/super-admin/usage')),
          ],
        );
      }),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Tenant Breakdown (side panel)
  // ═══════════════════════════════════════════════════════════

  Widget _buildTenantBreakdown(BuildContext context) {
    return _SectionCard(
      title: tr(context, 'sa_tenant_breakdown'),
      icon: Icons.pie_chart_outline,
      child: Column(children: [
        _BreakdownRow(label: tr(context, 'sa_plan_starter'), count: '8', pct: 0.33, color: AppColors.info),
        _BreakdownRow(label: tr(context, 'sa_plan_pro'), count: '10', pct: 0.42, color: AppColors.primary),
        _BreakdownRow(label: tr(context, 'sa_plan_enterprise'), count: '4', pct: 0.17, color: AppColors.success),
        _BreakdownRow(label: tr(context, 'sa_plan_trial'), count: '6', pct: 0.25, color: AppColors.warning),
        const Divider(height: 20),
        Row(children: [
          Text(tr(context, 'sa_total_tenants'), style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary)),
          const Spacer(),
          Text('24', style: AppTypography.labelLarge),
        ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  KPI Card with delta indicator
// ═══════════════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String delta;
  final bool deltaPositive;
  final Color color;
  const _KpiCard({required this.icon, required this.label, required this.value, required this.delta, required this.deltaPositive, required this.color});

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
        Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: color),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: (deltaPositive ? AppColors.success : AppColors.error).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(deltaPositive ? Icons.trending_up : Icons.trending_down, size: 12,
                color: deltaPositive ? AppColors.success : AppColors.error),
              const SizedBox(width: 3),
              Text(delta, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: deltaPositive ? AppColors.success : AppColors.error)),
            ]),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: AppTypography.headingSmall),
          Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
        ]),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Section Card
// ═══════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════
//  Activity Row
// ═══════════════════════════════════════════════════════════

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String time;
  final Color color;
  final String? badge;
  final Color? badgeColor;
  const _ActivityRow({required this.icon, required this.text, required this.time, required this.color, this.badge, this.badgeColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(children: [
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: color),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: AppTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (badge != null) ...[
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: (badgeColor ?? color).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(badge!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: badgeColor ?? color)),
            ),
          ],
        ],
      )),
      Text(time, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Alert Tile
// ═══════════════════════════════════════════════════════════

class _AlertTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String severity;
  final Color severityColor;
  const _AlertTile({required this.icon, required this.title, required this.subtitle, required this.color, required this.severity, required this.severityColor});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppTypography.labelSmall),
          Text(subtitle, style: AppTypography.caption.copyWith(color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: severityColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(severity, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: severityColor)),
        ),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Quick Action Card
// ═══════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════
//  Breakdown Row (tenant plan distribution)
// ═══════════════════════════════════════════════════════════

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
