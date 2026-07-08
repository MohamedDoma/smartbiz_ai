// SmartBiz AI — Super Admin Tenants Management screen.
// Mock tenants list with search, filters, status/plan badges, and actions.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../data/mock_tenants.dart';


// ═══════════════════════════════════════════════════════════
//  Tenants Screen
// ═══════════════════════════════════════════════════════════

class SuperAdminTenantsScreen extends StatefulWidget {
  const SuperAdminTenantsScreen({super.key});

  @override
  State<SuperAdminTenantsScreen> createState() => _SuperAdminTenantsScreenState();
}

class _SuperAdminTenantsScreenState extends State<SuperAdminTenantsScreen> {
  String _search = '';
  TenantStatus? _statusFilter;
  TenantPlan? _planFilter;

  List<MockTenant> get _filtered {
    return mockTenants.where((t) {
      if (_statusFilter != null && t.status != _statusFilter) return false;
      if (_planFilter != null && t.plan != _planFilter) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!t.name.toLowerCase().contains(q) &&
            !t.ownerEmail.toLowerCase().contains(q) &&
            !t.ownerName.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int _countByStatus(TenantStatus s) => mockTenants.where((t) => t.status == s).length;

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final filtered = _filtered;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────
              Text(tr(context, 'sat_title'), style: AppTypography.headingLarge),
              const SizedBox(height: 4),
              Text(tr(context, 'sat_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.lg),

              // ── Summary chips ──────────────────────────
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _SummaryChip(label: tr(context, 'sa_total_tenants'), value: '${mockTenants.length}', color: AppColors.primary),
                  _SummaryChip(label: tr(context, 'sat_status_active'), value: '${_countByStatus(TenantStatus.active)}', color: AppColors.success),
                  _SummaryChip(label: tr(context, 'sat_status_trial'), value: '${_countByStatus(TenantStatus.trial)}', color: AppColors.warning),
                  _SummaryChip(label: tr(context, 'sat_status_suspended'), value: '${_countByStatus(TenantStatus.suspended)}', color: AppColors.error),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Search + Filters ───────────────────────
              _buildSearchAndFilters(context, isMobile),
              const SizedBox(height: AppSpacing.lg),

              // ── Results count ──────────────────────────
              Text(
                '${filtered.length} ${tr(context, 'sat_results')}',
                style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: AppSpacing.sm),

              // ── Tenant list ────────────────────────────
              if (filtered.isEmpty)
                _buildEmptyState(context)
              else
                ...filtered.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _TenantCard(tenant: t, isMobile: isMobile, onAction: (action) => _handleAction(context, t, action)),
                )),

              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchAndFilters(BuildContext context, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search
        TextField(
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: tr(context, 'sat_search_hint'),
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.divider)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
          ),
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),

        // Filter row
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            // Status filter
            _FilterChip(
              label: tr(context, 'sat_filter_all'),
              selected: _statusFilter == null,
              onTap: () => setState(() => _statusFilter = null),
            ),
            _FilterChip(
              label: tr(context, 'sat_status_active'),
              selected: _statusFilter == TenantStatus.active,
              onTap: () => setState(() => _statusFilter = TenantStatus.active),
              color: AppColors.success,
            ),
            _FilterChip(
              label: tr(context, 'sat_status_trial'),
              selected: _statusFilter == TenantStatus.trial,
              onTap: () => setState(() => _statusFilter = TenantStatus.trial),
              color: AppColors.warning,
            ),
            _FilterChip(
              label: tr(context, 'sat_status_suspended'),
              selected: _statusFilter == TenantStatus.suspended,
              onTap: () => setState(() => _statusFilter = TenantStatus.suspended),
              color: AppColors.error,
            ),

            // Divider
            Container(width: 1, height: 28, color: AppColors.divider),

            // Plan filter
            _FilterChip(
              label: tr(context, 'sa_plan_starter'),
              selected: _planFilter == TenantPlan.starter,
              onTap: () => setState(() => _planFilter = _planFilter == TenantPlan.starter ? null : TenantPlan.starter),
              color: AppColors.info,
            ),
            _FilterChip(
              label: tr(context, 'sa_plan_pro'),
              selected: _planFilter == TenantPlan.professional,
              onTap: () => setState(() => _planFilter = _planFilter == TenantPlan.professional ? null : TenantPlan.professional),
              color: AppColors.primary,
            ),
            _FilterChip(
              label: tr(context, 'sa_plan_enterprise'),
              selected: _planFilter == TenantPlan.enterprise,
              onTap: () => setState(() => _planFilter = _planFilter == TenantPlan.enterprise ? null : TenantPlan.enterprise),
              color: AppColors.success,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: [
        Icon(Icons.search_off, size: 40, color: AppColors.neutral300),
        const SizedBox(height: AppSpacing.md),
        Text(tr(context, 'sat_no_results'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: AppSpacing.sm),
        TextButton(
          onPressed: () => setState(() { _search = ''; _statusFilter = null; _planFilter = null; }),
          child: Text(tr(context, 'sat_clear_filters')),
        ),
      ]),
    );
  }

  void _handleAction(BuildContext context, MockTenant tenant, String action) {
    if (action == 'view') {
      context.go('/super-admin/tenants/${tenant.id}');
      return;
    }
    final msg = switch (action) {
      'suspend' => '${tr(context, 'sat_action_suspend')}: ${tenant.name}',
      'activate' => '${tr(context, 'sat_action_activate')}: ${tenant.name}',
      'modules' => '${tr(context, 'sat_action_modules')}: ${tenant.name}',
      _ => action,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}

// ═══════════════════════════════════════════════════════════
//  Summary Chip
// ═══════════════════════════════════════════════════════════

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _SummaryChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.divider),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
        child: Center(child: Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
      ),
      const SizedBox(width: 8),
      Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Filter Chip
// ═══════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: selected ? c.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? c.withValues(alpha: 0.3) : AppColors.divider),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? c : AppColors.textSecondary)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Tenant Card
// ═══════════════════════════════════════════════════════════

class _TenantCard extends StatelessWidget {
  final MockTenant tenant;
  final bool isMobile;
  final void Function(String action) onAction;
  const _TenantCard({required this.tenant, required this.isMobile, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tenant.status == TenantStatus.suspended ? AppColors.error.withValues(alpha: 0.2) : AppColors.divider),
      ),
      child: isMobile ? _buildMobile(context) : _buildDesktop(context),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Row(
      children: [
        // Avatar
        _tenantAvatar(),
        const SizedBox(width: AppSpacing.md),

        // Name + email
        Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tenant.name, style: AppTypography.labelMedium),
          const SizedBox(height: 2),
          Text(tenant.ownerEmail, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: 4),
          Row(children: [
            _statusBadge(context),
            const SizedBox(width: 6),
            _planBadge(context),
          ]),
        ])),

        // Stats
        Expanded(flex: 3, child: Row(children: [
          _statCol(context, Icons.people_outline, '${tenant.usersCount}', tr(context, 'sat_col_users')),
          _statCol(context, Icons.extension_outlined, '${tenant.modulesEnabled}', tr(context, 'sat_col_modules')),
          _statCol(context, Icons.auto_awesome, '${tenant.aiRequests30d}', tr(context, 'sat_col_ai')),
        ])),

        // Dates
        Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _dateRow(context, Icons.calendar_today, tr(context, 'sat_col_created'), tenant.createdDate),
          const SizedBox(height: 4),
          _dateRow(context, Icons.access_time, tr(context, 'sat_col_last_active'), tenant.lastActive),
        ])),

        // Actions
        _actionMenu(context),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Top row: avatar + name + action
      Row(children: [
        _tenantAvatar(),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tenant.name, style: AppTypography.labelMedium),
          Text(tenant.ownerEmail, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
        ])),
        _actionMenu(context),
      ]),
      const SizedBox(height: AppSpacing.sm),

      // Badges
      Row(children: [
        _statusBadge(context),
        const SizedBox(width: 6),
        _planBadge(context),
      ]),
      const SizedBox(height: AppSpacing.sm),

      // Stats row
      Row(children: [
        _statChip(Icons.people_outline, '${tenant.usersCount}'),
        const SizedBox(width: AppSpacing.sm),
        _statChip(Icons.extension_outlined, '${tenant.modulesEnabled}'),
        const SizedBox(width: AppSpacing.sm),
        _statChip(Icons.auto_awesome, '${tenant.aiRequests30d}'),
        const Spacer(),
        Text(tenant.lastActive, style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
      ]),
    ]);
  }

  Widget _tenantAvatar() {
    final initial = tenant.name.isNotEmpty ? tenant.name[0].toUpperCase() : '?';
    final color = switch (tenant.status) {
      TenantStatus.active => AppColors.primary,
      TenantStatus.trial => AppColors.warning,
      TenantStatus.suspended => AppColors.neutral400,
    };
    return Container(
      width: 38, height: 38,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(initial, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color))),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final (labelKey, color) = switch (tenant.status) {
      TenantStatus.active => ('sat_status_active', AppColors.success),
      TenantStatus.trial => ('sat_status_trial', AppColors.warning),
      TenantStatus.suspended => ('sat_status_suspended', AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
      child: Text(tr(context, labelKey), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _planBadge(BuildContext context) {
    final (labelKey, color) = switch (tenant.plan) {
      TenantPlan.starter => ('sa_plan_starter', AppColors.info),
      TenantPlan.professional => ('sa_plan_pro', AppColors.primary),
      TenantPlan.enterprise => ('sa_plan_enterprise', AppColors.success),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(tr(context, labelKey), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: color)),
    );
  }

  Widget _statCol(BuildContext context, IconData icon, String value, String label) {
    return Expanded(child: Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: AppColors.textTertiary),
        const SizedBox(width: 3),
        Text(value, style: AppTypography.labelSmall),
      ]),
      Text(label, style: TextStyle(fontSize: 9, color: AppColors.textTertiary)),
    ]));
  }

  Widget _statChip(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: AppColors.textTertiary),
        const SizedBox(width: 3),
        Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _dateRow(BuildContext context, IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 11, color: AppColors.textTertiary),
      const SizedBox(width: 4),
      Text('$label: ', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
      Flexible(child: Text(value, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
    ]);
  }

  Widget _actionMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onAction,
      icon: const Icon(Icons.more_vert, size: 18, color: AppColors.neutral500),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'view', child: Row(children: [
          const Icon(Icons.visibility_outlined, size: 16), const SizedBox(width: 8),
          Text(tr(context, 'sat_action_view')),
        ])),
        if (tenant.status != TenantStatus.suspended)
          PopupMenuItem(value: 'suspend', child: Row(children: [
            const Icon(Icons.block, size: 16, color: AppColors.error), const SizedBox(width: 8),
            Text(tr(context, 'sat_action_suspend'), style: const TextStyle(color: AppColors.error)),
          ])),
        if (tenant.status == TenantStatus.suspended)
          PopupMenuItem(value: 'activate', child: Row(children: [
            const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success), const SizedBox(width: 8),
            Text(tr(context, 'sat_action_activate'), style: const TextStyle(color: AppColors.success)),
          ])),
        PopupMenuItem(value: 'modules', child: Row(children: [
          const Icon(Icons.extension_outlined, size: 16), const SizedBox(width: 8),
          Text(tr(context, 'sat_action_modules')),
        ])),
      ],
    );
  }
}
