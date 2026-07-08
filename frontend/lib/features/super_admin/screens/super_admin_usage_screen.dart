// SmartBiz AI — Super Admin AI Usage / Billing screen.
// Frontend mock for platform AI usage monitoring and billing overview.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../data/mock_tenants.dart';

class SuperAdminUsageScreen extends StatefulWidget {
  const SuperAdminUsageScreen({super.key});

  @override
  State<SuperAdminUsageScreen> createState() => _SuperAdminUsageScreenState();
}

// ═══════════════════════════════════════════════════════════
//  Mock AI usage data derived from tenant records
// ═══════════════════════════════════════════════════════════

class _TenantUsage {
  final MockTenant tenant;
  final int credits;
  final int quota;

  const _TenantUsage(this.tenant, this.credits, this.quota);

  double get pct => quota > 0 ? (credits / quota).clamp(0.0, 1.5) : 0;
  String get statusKey => pct > 1.0 ? 'sau_over' : (pct > 0.8 ? 'sau_warning' : 'sau_normal');
  Color get statusColor => pct > 1.0 ? AppColors.error : (pct > 0.8 ? AppColors.warning : AppColors.success);
}

List<_TenantUsage> _buildUsageData() {
  final quotas = <TenantPlan, int>{TenantPlan.starter: 1000, TenantPlan.professional: 5000, TenantPlan.enterprise: 20000};
  return mockTenants.map((t) {
    final q = quotas[t.plan] ?? 1000;
    return _TenantUsage(t, t.aiRequests30d, q);
  }).toList()..sort((a, b) => b.credits.compareTo(a.credits));
}

// ═══════════════════════════════════════════════════════════
//  Feature usage mock
// ═══════════════════════════════════════════════════════════

class _FeatureUsage {
  final String labelKey;
  final IconData icon;
  final int requests;
  final Color color;
  const _FeatureUsage(this.labelKey, this.icon, this.requests, this.color);
}

const _featureUsages = <_FeatureUsage>[
  _FeatureUsage('sau_feat_chat', Icons.chat_outlined, 8420, AppColors.primary),
  _FeatureUsage('sau_feat_advisor', Icons.psychology_outlined, 3150, AppColors.accent),
  _FeatureUsage('sau_feat_reports', Icons.analytics_outlined, 2080, AppColors.info),
  _FeatureUsage('sau_feat_blueprint', Icons.architecture_outlined, 950, AppColors.warning),
];

class _SuperAdminUsageScreenState extends State<SuperAdminUsageScreen> {
  String _search = '';
  int _periodDays = 30;
  late final List<_TenantUsage> _allUsage = _buildUsageData();

  List<_TenantUsage> get _filtered {
    if (_search.isEmpty) return _allUsage;
    final q = _search.toLowerCase();
    return _allUsage.where((u) =>
      u.tenant.name.toLowerCase().contains(q) ||
      u.tenant.ownerEmail.toLowerCase().contains(q)).toList();
  }

  int get _totalRequests => _allUsage.fold(0, (s, u) => s + u.credits);
  int get _totalCredits => _allUsage.fold(0, (s, u) => s + u.quota);
  int get _activeAiWorkspaces => _allUsage.where((u) => u.credits > 0).length;
  double get _estCost => _totalRequests * 0.002; // $0.002 per request mock

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final filtered = _filtered;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ─────────────────────────────────
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'sau_title'), style: AppTypography.headingLarge),
              const SizedBox(height: 4),
              Text(tr(context, 'sau_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            FilledButton.icon(
              onPressed: () => _snack(tr(context, 'sau_act_export')),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(tr(context, 'sau_act_export')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // ── Summary KPIs ──────────────────────────
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _SummaryCard(label: tr(context, 'sau_total_requests'), value: _fmtK(_totalRequests), icon: Icons.auto_awesome, color: AppColors.primary),
            _SummaryCard(label: tr(context, 'sau_credits_used'), value: '${(_totalRequests / _totalCredits * 100).toStringAsFixed(0)}%', icon: Icons.data_usage, color: AppColors.accent),
            _SummaryCard(label: tr(context, 'sau_active_ws'), value: '$_activeAiWorkspaces', icon: Icons.workspaces_outlined, color: AppColors.info),
            _SummaryCard(label: tr(context, 'sau_est_cost'), value: '\$${_estCost.toStringAsFixed(0)}', icon: Icons.attach_money, color: AppColors.success),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // ── Filters ───────────────────────────────
          _buildFilters(context),
          const SizedBox(height: AppSpacing.lg),

          // ── Alerts ────────────────────────────────
          _buildAlerts(context),
          const SizedBox(height: AppSpacing.lg),

          // ── Tenant usage list ─────────────────────
          Text('${tr(context, 'sau_tenant_usage')} (${filtered.length})', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _buildTenantTable(filtered),
          const SizedBox(height: AppSpacing.xl),

          // ── Feature usage ─────────────────────────
          Text(tr(context, 'sau_feature_usage'), style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _buildFeatureUsage(context),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  // ── Filters ──────────────────────────────────────────────

  Widget _buildFilters(BuildContext context) {
    return Row(children: [
      Expanded(child: TextField(
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: tr(context, 'sau_search_hint'),
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true, fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
        ),
        style: AppTypography.bodySmall,
      )),
      const SizedBox(width: AppSpacing.sm),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(value: 7, label: Text(tr(context, 'sau_7d'), style: const TextStyle(fontSize: 11))),
          ButtonSegment(value: 30, label: Text(tr(context, 'sau_30d'), style: const TextStyle(fontSize: 11))),
          ButtonSegment(value: 180, label: Text(tr(context, 'sau_6m'), style: const TextStyle(fontSize: 11))),
          ButtonSegment(value: 365, label: Text(tr(context, 'sau_1y'), style: const TextStyle(fontSize: 11))),
        ],
        selected: {_periodDays},
        onSelectionChanged: (s) => setState(() => _periodDays = s.first),
      ),
    ]);
  }

  // ── Alerts ───────────────────────────────────────────────

  Widget _buildAlerts(BuildContext context) {
    final overLimit = _allUsage.where((u) => u.pct > 1.0).toList();
    final nearLimit = _allUsage.where((u) => u.pct > 0.8 && u.pct <= 1.0).toList();

    if (overLimit.isEmpty && nearLimit.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.warning_amber_rounded, size: 17, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Text(tr(context, 'sau_alerts'), style: AppTypography.labelLarge),
        ]),
        const SizedBox(height: AppSpacing.sm),
        ...overLimit.map((u) => _AlertRow(
          icon: Icons.error_outline, color: AppColors.error,
          text: '${u.tenant.name}: ${tr(context, 'sau_alert_over')} (${(u.pct * 100).toStringAsFixed(0)}%)',
          onAction: () => _snack('${tr(context, 'sau_act_adjust')}: ${u.tenant.name}'),
        )),
        ...nearLimit.map((u) => _AlertRow(
          icon: Icons.warning_amber, color: AppColors.warning,
          text: '${u.tenant.name}: ${tr(context, 'sau_alert_near')} (${(u.pct * 100).toStringAsFixed(0)}%)',
          onAction: () => _snack('${tr(context, 'sau_act_adjust')}: ${u.tenant.name}'),
        )),
        _AlertRow(
          icon: Icons.receipt_long_outlined, color: AppColors.info,
          text: tr(context, 'sau_alert_billing'),
          onAction: () => _snack(tr(context, 'sau_act_billing')),
        ),
      ]),
    );
  }

  // ── Tenant Usage Table ───────────────────────────────────

  Widget _buildTenantTable(List<_TenantUsage> data) {
    if (data.isEmpty) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
        child: Column(children: [
          const Icon(Icons.search_off, size: 40, color: AppColors.neutral300),
          const SizedBox(height: AppSpacing.md),
          Text(tr(context, 'sau_no_results'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 700),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppColors.neutral100),
          headingTextStyle: AppTypography.labelSmall,
          dataTextStyle: AppTypography.bodySmall,
          columnSpacing: 16,
          columns: [
            DataColumn(label: Text(tr(context, 'sau_col_workspace'))),
            DataColumn(label: Text(tr(context, 'sau_col_plan'))),
            DataColumn(label: Text(tr(context, 'sau_col_requests')), numeric: true),
            DataColumn(label: Text(tr(context, 'sau_col_quota')), numeric: true),
            DataColumn(label: Text(tr(context, 'sau_col_usage'))),
            DataColumn(label: Text(tr(context, 'sau_col_status'))),
            DataColumn(label: Text(tr(context, 'sau_col_actions'))),
          ],
          rows: data.map((u) => DataRow(cells: [
            DataCell(Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(u.tenant.name, style: AppTypography.labelSmall),
              Text(u.tenant.ownerEmail, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ])),
            DataCell(_PlanBadge(plan: u.tenant.plan)),
            DataCell(Text('${u.credits}', style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text('${u.quota}')),
            DataCell(SizedBox(width: 80, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: u.pct.clamp(0.0, 1.0), backgroundColor: AppColors.neutral100, color: u.statusColor, minHeight: 6)),
              const SizedBox(height: 2),
              Text('${(u.pct * 100).toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: u.statusColor)),
            ]))),
            DataCell(Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: u.statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(tr(context, u.statusKey), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: u.statusColor)),
            )),
            DataCell(PopupMenuButton<String>(
              onSelected: (a) => _tenantAction(u, a),
              icon: const Icon(Icons.more_vert, size: 16, color: AppColors.neutral500),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sau_act_view'))])),
                PopupMenuItem(value: 'adjust', child: Row(children: [const Icon(Icons.tune, size: 16), const SizedBox(width: 8), Text(tr(context, 'sau_act_adjust'))])),
                PopupMenuItem(value: 'billing', child: Row(children: [const Icon(Icons.receipt_long, size: 16), const SizedBox(width: 8), Text(tr(context, 'sau_act_billing'))])),
              ],
            )),
          ])).toList(),
        ),
      )),
    );
  }

  void _tenantAction(_TenantUsage u, String action) {
    final msg = switch (action) {
      'view' => '${tr(context, 'sau_act_view')}: ${u.tenant.name}',
      'adjust' => '${tr(context, 'sau_act_adjust')}: ${u.tenant.name}',
      'billing' => '${tr(context, 'sau_act_billing')}: ${u.tenant.name}',
      _ => action,
    };
    _snack(msg);
  }

  // ── Feature Usage ────────────────────────────────────────

  Widget _buildFeatureUsage(BuildContext context) {
    final maxReq = _featureUsages.map((f) => f.requests).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ..._featureUsages.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(children: [
            Container(width: 34, height: 34,
              decoration: BoxDecoration(color: f.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(f.icon, size: 17, color: f.color)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(tr(context, f.labelKey), style: AppTypography.labelSmall)),
                Text(_fmtK(f.requests), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: f.color)),
              ]),
              const SizedBox(height: 4),
              ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: f.requests / maxReq, backgroundColor: AppColors.neutral100, color: f.color, minHeight: 6)),
            ])),
          ]),
        )),
      ]),
    );
  }

  String _fmtK(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}K' : '$n';
}

// ═══════════════════════════════════════════════════════════
//  Summary Card
// ═══════════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label; final String value; final IconData icon; final Color color;
  const _SummaryCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 15, color: color)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ]),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Plan Badge
// ═══════════════════════════════════════════════════════════

class _PlanBadge extends StatelessWidget {
  final TenantPlan plan;
  const _PlanBadge({required this.plan});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (plan) {
      TenantPlan.starter => ('Starter', AppColors.info),
      TenantPlan.professional => ('Pro', AppColors.primary),
      TenantPlan.enterprise => ('Enterprise', AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Alert Row
// ═══════════════════════════════════════════════════════════

class _AlertRow extends StatelessWidget {
  final IconData icon; final Color color; final String text; final VoidCallback onAction;
  const _AlertRow({required this.icon, required this.color, required this.text, required this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
      TextButton(
        onPressed: onAction,
        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), minimumSize: Size.zero),
        child: Text(tr(context, 'sau_act_review'), style: const TextStyle(fontSize: 11)),
      ),
    ]),
  );
}
