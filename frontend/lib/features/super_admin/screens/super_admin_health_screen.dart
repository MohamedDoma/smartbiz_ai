// SmartBiz AI — Super Admin System Health & Audit Logs screen.
// Frontend mock for platform monitoring, service health, and audit trail.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';

// ═══════════════════════════════════════════════════════════
//  Mock Data Models
// ═══════════════════════════════════════════════════════════

enum ServiceStatus { operational, degraded, down }
enum LogSeverity { info, warning, critical }

class _ServiceHealth {
  final String nameKey;
  final IconData icon;
  final ServiceStatus status;
  final String latency;
  final String lastChecked;

  const _ServiceHealth(this.nameKey, this.icon, this.status, this.latency, this.lastChecked);

  Color get statusColor => switch (status) {
    ServiceStatus.operational => AppColors.success,
    ServiceStatus.degraded => AppColors.warning,
    ServiceStatus.down => AppColors.error,
  };

  String statusKey() => switch (status) {
    ServiceStatus.operational => 'sah_operational',
    ServiceStatus.degraded => 'sah_degraded',
    ServiceStatus.down => 'sah_down',
  };
}

class _AuditLog {
  final String timestamp;
  final String actor;
  final String action;
  final String target;
  final LogSeverity severity;

  const _AuditLog(this.timestamp, this.actor, this.action, this.target, this.severity);

  Color get sevColor => switch (severity) {
    LogSeverity.info => AppColors.info,
    LogSeverity.warning => AppColors.warning,
    LogSeverity.critical => AppColors.error,
  };

  String sevKey() => switch (severity) {
    LogSeverity.info => 'sah_sev_info',
    LogSeverity.warning => 'sah_sev_warning',
    LogSeverity.critical => 'sah_sev_critical',
  };
}

// ═══════════════════════════════════════════════════════════
//  Seed Data
// ═══════════════════════════════════════════════════════════

const _services = <_ServiceHealth>[
  _ServiceHealth('sah_svc_api', Icons.api, ServiceStatus.operational, '42ms', '2m ago'),
  _ServiceHealth('sah_svc_db', Icons.storage, ServiceStatus.operational, '8ms', '1m ago'),
  _ServiceHealth('sah_svc_queue', Icons.queue, ServiceStatus.operational, '15ms', '3m ago'),
  _ServiceHealth('sah_svc_storage', Icons.cloud_outlined, ServiceStatus.operational, '120ms', '5m ago'),
  _ServiceHealth('sah_svc_ai', Icons.psychology, ServiceStatus.degraded, '890ms', '30s ago'),
  _ServiceHealth('sah_svc_email', Icons.email_outlined, ServiceStatus.operational, '210ms', '4m ago'),
  _ServiceHealth('sah_svc_payments', Icons.payment, ServiceStatus.operational, '95ms', '2m ago'),
  _ServiceHealth('sah_svc_cdn', Icons.public, ServiceStatus.operational, '35ms', '1m ago'),
];

const _auditLogs = <_AuditLog>[
  _AuditLog('2026-07-04 10:32:15', 'System', 'AI service latency spike detected', 'AI Gateway', LogSeverity.warning),
  _AuditLog('2026-07-04 10:28:44', 'admin@smartbiz.ai', 'Plan upgraded for Delta Logistics', 'Tenant: Delta Logistics', LogSeverity.info),
  _AuditLog('2026-07-04 10:15:03', 'System', 'Database backup completed', 'PostgreSQL Primary', LogSeverity.info),
  _AuditLog('2026-07-04 09:58:22', 'admin@smartbiz.ai', 'Module "Fleet Management" draft created', 'Module Registry', LogSeverity.info),
  _AuditLog('2026-07-04 09:45:11', 'System', 'Rate limit threshold reached', 'API Gateway', LogSeverity.warning),
  _AuditLog('2026-07-04 09:30:00', 'admin@smartbiz.ai', 'Tenant suspended: Quick Fix LLC', 'Tenant: Quick Fix LLC', LogSeverity.critical),
  _AuditLog('2026-07-04 09:12:33', 'System', 'SSL certificate renewal successful', 'CDN / TLS', LogSeverity.info),
  _AuditLog('2026-07-04 08:55:17', 'admin@smartbiz.ai', 'New plan "Custom Enterprise" created', 'Plans', LogSeverity.info),
  _AuditLog('2026-07-04 08:40:05', 'System', 'Disk usage above 80% threshold', 'Storage Node 2', LogSeverity.warning),
  _AuditLog('2026-07-04 08:22:49', 'System', 'Failed login attempts from unknown IP', 'Auth Service', LogSeverity.critical),
  _AuditLog('2026-07-04 08:10:00', 'admin@smartbiz.ai', 'AI credit quota adjusted for Acme Corp', 'Tenant: Acme Corp', LogSeverity.info),
  _AuditLog('2026-07-04 07:50:33', 'System', 'Scheduled maintenance window started', 'Platform', LogSeverity.info),
];

// ═══════════════════════════════════════════════════════════
//  Screen
// ═══════════════════════════════════════════════════════════

class SuperAdminHealthScreen extends StatefulWidget {
  const SuperAdminHealthScreen({super.key});

  @override
  State<SuperAdminHealthScreen> createState() => _SuperAdminHealthScreenState();
}

class _SuperAdminHealthScreenState extends State<SuperAdminHealthScreen> {
  String _logSearch = '';
  LogSeverity? _sevFilter;
  ServiceStatus? _svcFilter;

  List<_AuditLog> get _filteredLogs {
    return _auditLogs.where((l) {
      if (_sevFilter != null && l.severity != _sevFilter) return false;
      if (_logSearch.isNotEmpty) {
        final q = _logSearch.toLowerCase();
        if (!l.action.toLowerCase().contains(q) &&
            !l.actor.toLowerCase().contains(q) &&
            !l.target.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<_ServiceHealth> get _filteredServices {
    if (_svcFilter == null) return _services;
    return _services.where((s) => s.status == _svcFilter).toList();
  }

  int _countStatus(ServiceStatus s) => _services.where((sv) => sv.status == s).length;

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)));

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final logs = _filteredLogs;
    final services = _filteredServices;
    final opCount = _countStatus(ServiceStatus.operational);

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Header ─────────────────────────────────
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'sah_title'), style: AppTypography.headingLarge),
              const SizedBox(height: 4),
              Text(tr(context, 'sah_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
            FilledButton.icon(
              onPressed: () => _snack(tr(context, 'sah_act_export')),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: Text(tr(context, 'sah_act_export')),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),

          // ── System Status KPIs ─────────────────────
          Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
            _KpiCard(label: tr(context, 'sah_kpi_api'), value: '42ms', icon: Icons.api, color: AppColors.success),
            _KpiCard(label: tr(context, 'sah_kpi_db'), value: '8ms', icon: Icons.storage, color: AppColors.success),
            _KpiCard(label: tr(context, 'sah_kpi_queue'), value: '0', icon: Icons.queue, color: AppColors.success, sub: tr(context, 'sah_kpi_pending')),
            _KpiCard(label: tr(context, 'sah_kpi_storage'), value: '72%', icon: Icons.cloud_outlined, color: AppColors.warning),
            _KpiCard(label: tr(context, 'sah_kpi_ai'), value: '890ms', icon: Icons.psychology, color: AppColors.warning),
            _KpiCard(label: tr(context, 'sah_kpi_uptime'), value: '99.94%', icon: Icons.timer_outlined, color: AppColors.success),
          ]),
          const SizedBox(height: AppSpacing.xl),

          // ── Service Health ─────────────────────────
          Row(children: [
            Expanded(child: Text(tr(context, 'sah_services'), style: AppTypography.labelLarge)),
            _StatusChip(label: '$opCount/${_services.length} ${tr(context, 'sah_operational')}',
              color: opCount == _services.length ? AppColors.success : AppColors.warning),
          ]),
          const SizedBox(height: AppSpacing.sm),
          _buildServiceFilters(),
          const SizedBox(height: AppSpacing.sm),
          LayoutBuilder(builder: (_, c) {
            final cols = c.maxWidth > 700 ? 2 : 1;
            return GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols, mainAxisSpacing: AppSpacing.sm,
                crossAxisSpacing: AppSpacing.sm, mainAxisExtent: 72),
              itemCount: services.length,
              itemBuilder: (_, i) => _buildServiceRow(services[i]),
            );
          }),
          const SizedBox(height: AppSpacing.xl),

          // ── Audit Logs ─────────────────────────────
          Text('${tr(context, 'sah_audit_logs')} (${logs.length})', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          _buildLogFilters(),
          const SizedBox(height: AppSpacing.sm),
          _buildLogList(logs),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }

  // ── Service Filters ──────────────────────────────────────

  Widget _buildServiceFilters() {
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
      _FilterChip(label: tr(context, 'sah_all'), selected: _svcFilter == null,
        onTap: () => setState(() => _svcFilter = null)),
      const SizedBox(width: 6),
      _FilterChip(label: tr(context, 'sah_operational'), selected: _svcFilter == ServiceStatus.operational,
        color: AppColors.success, onTap: () => setState(() => _svcFilter = _svcFilter == ServiceStatus.operational ? null : ServiceStatus.operational)),
      const SizedBox(width: 6),
      _FilterChip(label: tr(context, 'sah_degraded'), selected: _svcFilter == ServiceStatus.degraded,
        color: AppColors.warning, onTap: () => setState(() => _svcFilter = _svcFilter == ServiceStatus.degraded ? null : ServiceStatus.degraded)),
      const SizedBox(width: 6),
      _FilterChip(label: tr(context, 'sah_down'), selected: _svcFilter == ServiceStatus.down,
        color: AppColors.error, onTap: () => setState(() => _svcFilter = _svcFilter == ServiceStatus.down ? null : ServiceStatus.down)),
    ]));
  }

  // ── Service Row ──────────────────────────────────────────

  Widget _buildServiceRow(_ServiceHealth s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: s.statusColor, shape: BoxShape.circle)),
        const SizedBox(width: AppSpacing.sm),
        Container(width: 32, height: 32,
          decoration: BoxDecoration(color: s.statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
          child: Icon(s.icon, size: 16, color: s.statusColor)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(tr(context, s.nameKey), style: AppTypography.labelSmall),
          Text('${tr(context, 'sah_latency')}: ${s.latency}', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: s.statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
            child: Text(tr(context, s.statusKey()), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: s.statusColor))),
          const SizedBox(height: 2),
          Text(s.lastChecked, style: TextStyle(fontSize: 9, color: AppColors.textTertiary)),
        ]),
      ]),
    );
  }

  // ── Log Filters ──────────────────────────────────────────

  Widget _buildLogFilters() {
    return Row(children: [
      Expanded(child: TextField(
        onChanged: (v) => setState(() => _logSearch = v),
        decoration: InputDecoration(
          hintText: tr(context, 'sah_search_hint'),
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
      SegmentedButton<LogSeverity?>(
        segments: [
          ButtonSegment(value: null, label: Text(tr(context, 'sah_all'), style: const TextStyle(fontSize: 11))),
          ButtonSegment(value: LogSeverity.info, label: Text(tr(context, 'sah_sev_info'), style: const TextStyle(fontSize: 11))),
          ButtonSegment(value: LogSeverity.warning, label: Text(tr(context, 'sah_sev_warning'), style: const TextStyle(fontSize: 11))),
          ButtonSegment(value: LogSeverity.critical, label: Text(tr(context, 'sah_sev_critical'), style: const TextStyle(fontSize: 11))),
        ],
        selected: {_sevFilter},
        onSelectionChanged: (s) => setState(() => _sevFilter = s.first),
      ),
    ]);
  }

  // ── Log List ─────────────────────────────────────────────

  Widget _buildLogList(List<_AuditLog> logs) {
    if (logs.isEmpty) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
        child: Column(children: [
          const Icon(Icons.search_off, size: 40, color: AppColors.neutral300),
          const SizedBox(height: AppSpacing.md),
          Text(tr(context, 'sah_no_logs'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.divider)),
      child: ListView.separated(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        itemCount: logs.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _buildLogRow(logs[i]),
      ),
    );
  }

  Widget _buildLogRow(_AuditLog log) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: log.sevColor, shape: BoxShape.circle)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(log.action, style: AppTypography.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: log.sevColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(3)),
              child: Text(tr(context, log.sevKey()), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: log.sevColor))),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Text(log.timestamp, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            const SizedBox(width: 8),
            const Icon(Icons.person_outline, size: 10, color: AppColors.textTertiary),
            const SizedBox(width: 2),
            Expanded(child: Text(log.actor, style: TextStyle(fontSize: 10, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Icon(Icons.arrow_right_alt, size: 10, color: AppColors.textTertiary),
            const SizedBox(width: 2),
            Expanded(child: Text(log.target, style: TextStyle(fontSize: 10, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ])),
        PopupMenuButton<String>(
          onSelected: (a) {
            final msg = switch (a) {
              'view' => '${tr(context, 'sah_act_view')}: ${log.action}',
              'ack' => '${tr(context, 'sah_act_ack')}: ${log.action}',
              _ => a,
            };
            _snack(msg);
          },
          icon: const Icon(Icons.more_vert, size: 14, color: AppColors.neutral500),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility_outlined, size: 16), const SizedBox(width: 8), Text(tr(context, 'sah_act_view'))])),
            if (log.severity != LogSeverity.info)
              PopupMenuItem(value: 'ack', child: Row(children: [const Icon(Icons.check_circle_outline, size: 16), const SizedBox(width: 8), Text(tr(context, 'sah_act_ack'))])),
          ],
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  KPI Card
// ═══════════════════════════════════════════════════════════

class _KpiCard extends StatelessWidget {
  final String label; final String value; final IconData icon; final Color color; final String? sub;
  const _KpiCard({required this.label, required this.value, required this.icon, required this.color, this.sub});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 30, height: 30, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
        child: Icon(icon, size: 15, color: color)),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          if (sub != null) Text('  $sub', style: TextStyle(fontSize: 9, color: AppColors.textTertiary)),
        ]),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ]),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  Status Chip
// ═══════════════════════════════════════════════════════════

class _StatusChip extends StatelessWidget {
  final String label; final Color color;
  const _StatusChip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );
}

// ═══════════════════════════════════════════════════════════
//  Filter Chip
// ═══════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap; final Color? color;
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: selected ? c.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: selected ? c.withValues(alpha: 0.3) : AppColors.divider)),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w600 : FontWeight.w400, color: selected ? c : AppColors.textSecondary)),
        ),
      ),
    );
  }
}
