// SmartBiz AI — Super Admin Tenant Detail screen.
// Shows full tenant overview with modules, activity, billing, and actions.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../data/mock_tenants.dart';

class SuperAdminTenantDetailScreen extends StatelessWidget {
  final String tenantId;
  const SuperAdminTenantDetailScreen({super.key, required this.tenantId});

  @override
  Widget build(BuildContext context) {
    final tenant = findTenantById(tenantId);
    if (tenant == null) return _NotFound(tenantId: tenantId);

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
              // ── Back + Header ───────────────────────────
              _buildHeader(context, tenant),
              const SizedBox(height: AppSpacing.xl),

              // ── Main content ───────────────────────────
              if (isDesktop)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: Column(children: [
                    _buildOverviewCard(context, tenant),
                    const SizedBox(height: AppSpacing.lg),
                    _buildModulesCard(context, tenant),
                    const SizedBox(height: AppSpacing.lg),
                    _buildActivityCard(context, tenant),
                  ])),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: Column(children: [
                    _buildActionsCard(context, tenant),
                    const SizedBox(height: AppSpacing.lg),
                    _buildBillingCard(context, tenant),
                    const SizedBox(height: AppSpacing.lg),
                    _buildUsageCard(context, tenant),
                  ])),
                ])
              else ...[
                _buildOverviewCard(context, tenant),
                const SizedBox(height: AppSpacing.lg),
                _buildActionsCard(context, tenant),
                const SizedBox(height: AppSpacing.lg),
                _buildModulesCard(context, tenant),
                const SizedBox(height: AppSpacing.lg),
                _buildBillingCard(context, tenant),
                const SizedBox(height: AppSpacing.lg),
                _buildUsageCard(context, tenant),
                const SizedBox(height: AppSpacing.lg),
                _buildActivityCard(context, tenant),
              ],

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Header
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, MockTenant tenant) {
    final statusColor = _statusColor(tenant.status);
    final statusKey = _statusKey(tenant.status);
    final planKey = _planKey(tenant.plan);
    final planColor = _planColor(tenant.plan);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Back link
      InkWell(
        onTap: () => context.go('/super-admin/tenants'),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(tr(context, 'satd_back'), style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
      const SizedBox(height: AppSpacing.md),

      // Name + badges
      Row(children: [
        _avatar(tenant, 48),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tenant.name, style: AppTypography.headingLarge),
          const SizedBox(height: 4),
          Row(children: [
            Text('${tenant.ownerName}  •  ${tenant.ownerEmail}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _badge(tr(context, statusKey), statusColor, filled: true),
            const SizedBox(width: 6),
            _badge(tr(context, planKey), planColor, filled: false),
          ]),
        ])),
      ]),
    ]);
  }

  // ═══════════════════════════════════════════════════════════
  //  Overview
  // ═══════════════════════════════════════════════════════════

  Widget _buildOverviewCard(BuildContext context, MockTenant tenant) {
    return _Card(title: tr(context, 'satd_overview'), icon: Icons.info_outline, child: Column(children: [
      _InfoRow(label: tr(context, 'satd_workspace_id'), value: tenant.id),
      _InfoRow(label: tr(context, 'sat_col_created'), value: tenant.createdDate),
      _InfoRow(label: tr(context, 'sat_col_last_active'), value: tenant.lastActive),
      _InfoRow(label: tr(context, 'sat_col_users'), value: '${tenant.usersCount}'),
      _InfoRow(label: tr(context, 'sat_col_modules'), value: '${tenant.modulesEnabled}'),
      _InfoRow(label: tr(context, 'sat_col_ai'), value: '${tenant.aiRequests30d}'),
    ]));
  }

  // ═══════════════════════════════════════════════════════════
  //  Modules
  // ═══════════════════════════════════════════════════════════

  Widget _buildModulesCard(BuildContext context, MockTenant tenant) {
    return _Card(
      title: tr(context, 'satd_enabled_modules'),
      icon: Icons.extension_outlined,
      trailing: Text('${tenant.enabledModules.length}', style: AppTypography.labelSmall.copyWith(color: AppColors.primary)),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: tenant.enabledModules.map((m) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, size: 13, color: AppColors.primary),
            const SizedBox(width: 5),
            Text(m, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary)),
          ]),
        )).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  //  Activity
  // ═══════════════════════════════════════════════════════════

  Widget _buildActivityCard(BuildContext context, MockTenant tenant) {
    return _Card(title: tr(context, 'satd_activity'), icon: Icons.history, child: Column(children: [
      _ActivityItem(icon: Icons.person_add, text: tr(context, 'satd_act_user_added'), time: tr(context, 'sa_time_2h'), color: AppColors.success),
      _ActivityItem(icon: Icons.extension, text: tr(context, 'satd_act_module_change'), time: tr(context, 'sa_time_1d'), color: AppColors.accent),
      _ActivityItem(icon: Icons.auto_awesome, text: tr(context, 'satd_act_ai_usage'), time: tr(context, 'sa_time_2d'), color: AppColors.warning),
      _ActivityItem(icon: Icons.login, text: tr(context, 'satd_act_login'), time: tr(context, 'sa_time_2d'), color: AppColors.info),
    ]));
  }

  // ═══════════════════════════════════════════════════════════
  //  Actions
  // ═══════════════════════════════════════════════════════════

  Widget _buildActionsCard(BuildContext context, MockTenant tenant) {
    return _Card(title: tr(context, 'satd_actions'), icon: Icons.flash_on_outlined, child: Column(children: [
      if (tenant.status != TenantStatus.suspended)
        _ActionButton(icon: Icons.block, label: tr(context, 'sat_action_suspend'), color: AppColors.error,
          onTap: () => _snack(context, tr(context, 'sat_action_suspend'))),
      if (tenant.status == TenantStatus.suspended)
        _ActionButton(icon: Icons.check_circle_outline, label: tr(context, 'sat_action_activate'), color: AppColors.success,
          onTap: () => _snack(context, tr(context, 'sat_action_activate'))),
      _ActionButton(icon: Icons.extension_outlined, label: tr(context, 'sat_action_modules'), color: AppColors.accent,
        onTap: () => _snack(context, tr(context, 'sat_action_modules'))),
      _ActionButton(icon: Icons.card_membership, label: tr(context, 'satd_change_plan'), color: AppColors.primary,
        onTap: () => _snack(context, tr(context, 'satd_change_plan'))),
    ]));
  }

  // ═══════════════════════════════════════════════════════════
  //  Billing
  // ═══════════════════════════════════════════════════════════

  Widget _buildBillingCard(BuildContext context, MockTenant tenant) {
    final planKey = _planKey(tenant.plan);
    final planColor = _planColor(tenant.plan);
    final price = switch (tenant.plan) {
      TenantPlan.starter => '\$29',
      TenantPlan.professional => '\$79',
      TenantPlan.enterprise => '\$199',
    };

    return _Card(title: tr(context, 'satd_billing'), icon: Icons.payments_outlined, child: Column(children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(context, 'satd_current_plan'), style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 2),
          Row(children: [
            _badge(tr(context, planKey), planColor, filled: true),
            const SizedBox(width: 8),
            Text('$price${tr(context, 'satd_per_month')}', style: AppTypography.labelSmall),
          ]),
        ])),
      ]),
      const Divider(height: 20),
      _InfoRow(label: tr(context, 'satd_billing_status'), value: tenant.status == TenantStatus.suspended ? tr(context, 'satd_billing_overdue') : tr(context, 'satd_billing_current')),
      _InfoRow(label: tr(context, 'satd_next_billing'), value: '2025-08-01'),
    ]));
  }

  // ═══════════════════════════════════════════════════════════
  //  AI Usage
  // ═══════════════════════════════════════════════════════════

  Widget _buildUsageCard(BuildContext context, MockTenant tenant) {
    final quota = switch (tenant.plan) {
      TenantPlan.starter => 1000,
      TenantPlan.professional => 5000,
      TenantPlan.enterprise => 20000,
    };
    final pct = tenant.aiRequests30d / quota;
    final pctStr = '${(pct * 100).toStringAsFixed(0)}%';
    final barColor = pct > 0.85 ? AppColors.error : (pct > 0.6 ? AppColors.warning : AppColors.success);

    return _Card(title: tr(context, 'satd_ai_usage'), icon: Icons.auto_awesome, child: Column(children: [
      Row(children: [
        Expanded(child: Text('${tenant.aiRequests30d} / $quota', style: AppTypography.labelMedium)),
        Text(pctStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: barColor)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0), backgroundColor: AppColors.neutral100, color: barColor, minHeight: 8),
      ),
      const SizedBox(height: 8),
      Text(tr(context, 'satd_ai_quota_label'), style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
    ]));
  }

  // ── Helpers ────────────────────────────────────────────

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$msg: ${findTenantById(tenantId)?.name ?? tenantId}'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _avatar(MockTenant t, double size) {
    final initial = t.name.isNotEmpty ? t.name[0].toUpperCase() : '?';
    final color = _statusColor(t.status);
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(size * 0.26)),
      child: Center(child: Text(initial, style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.w700, color: color))),
    );
  }

  Widget _badge(String text, Color color, {required bool filled}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? color.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
      border: filled ? null : Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );

  Color _statusColor(TenantStatus s) => switch (s) {
    TenantStatus.active => AppColors.success,
    TenantStatus.trial => AppColors.warning,
    TenantStatus.suspended => AppColors.error,
  };

  String _statusKey(TenantStatus s) => switch (s) {
    TenantStatus.active => 'sat_status_active',
    TenantStatus.trial => 'sat_status_trial',
    TenantStatus.suspended => 'sat_status_suspended',
  };

  Color _planColor(TenantPlan p) => switch (p) {
    TenantPlan.starter => AppColors.info,
    TenantPlan.professional => AppColors.primary,
    TenantPlan.enterprise => AppColors.success,
  };

  String _planKey(TenantPlan p) => switch (p) {
    TenantPlan.starter => 'sa_plan_starter',
    TenantPlan.professional => 'sa_plan_pro',
    TenantPlan.enterprise => 'sa_plan_enterprise',
  };
}

// ═══════════════════════════════════════════════════════════
//  Not Found
// ═══════════════════════════════════════════════════════════

class _NotFound extends StatelessWidget {
  final String tenantId;
  const _NotFound({required this.tenantId});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.business_outlined, size: 56, color: AppColors.neutral300),
        const SizedBox(height: AppSpacing.lg),
        Text(tr(context, 'satd_not_found'), style: AppTypography.headingSmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        Text('ID: $tenantId', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => context.go('/super-admin/tenants'),
          icon: const Icon(Icons.arrow_back, size: 16),
          label: Text(tr(context, 'satd_back')),
        ),
      ]),
    ),
  );
}

// ═══════════════════════════════════════════════════════════
//  Section Card
// ═══════════════════════════════════════════════════════════

class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  const _Card({required this.title, required this.icon, required this.child, this.trailing});

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
        Icon(icon, size: 17, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTypography.labelLarge)),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: AppSpacing.md),
      child,
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Info Row
// ═══════════════════════════════════════════════════════════

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Expanded(flex: 2, child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.textTertiary))),
      Expanded(flex: 3, child: Text(value, style: AppTypography.bodySmall)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Activity Item
// ═══════════════════════════════════════════════════════════

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String text;
  final String time;
  final Color color;
  const _ActivityItem({required this.icon, required this.text, required this.time, required this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 14, color: color),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, style: AppTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
      Text(time, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Action Button
// ═══════════════════════════════════════════════════════════

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
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
    ),
  );
}
