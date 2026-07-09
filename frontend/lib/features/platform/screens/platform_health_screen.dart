// SmartBiz AI — Platform System Health screen (Step 58.1).
// Real data from GET /api/platform/system-health.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../platform/platform_state.dart';

class PlatformHealthScreen extends StatefulWidget {
  const PlatformHealthScreen({super.key});
  @override
  State<PlatformHealthScreen> createState() => _State();
}

class _State extends State<PlatformHealthScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<PlatformState>().loadHealth());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<PlatformState>();

    if (s.healthLoading) return const Center(child: CircularProgressIndicator());
    if (s.healthData == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.warning),
        const SizedBox(height: 12),
        Text(tr(context, 'plt_load_failed'), style: AppTypography.bodyMedium),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => s.loadHealth(), child: Text(tr(context, 'gen_retry'))),
      ]));
    }

    final data = s.healthData!;
    final overall = data['overall'] ?? 'unknown';
    final checks = (data['checks'] as Map<String, dynamic>?) ?? {};
    final ts = data['timestamp'] ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Overall status
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: overall == 'healthy'
                    ? AppColors.success.withValues(alpha: 0.08)
                    : AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: overall == 'healthy'
                    ? AppColors.success.withValues(alpha: 0.2)
                    : AppColors.warning.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                Icon(
                  overall == 'healthy' ? Icons.check_circle : Icons.warning,
                  size: 40,
                  color: overall == 'healthy' ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.md),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    overall == 'healthy' ? tr(context, 'sa_status_healthy') : tr(context, 'plt_status_degraded'),
                    style: AppTypography.headingSmall,
                  ),
                  Text(ts.length > 19 ? ts.substring(0, 19) : ts, style: AppTypography.caption),
                ]),
              ]),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Individual checks
            ...checks.entries.map((e) {
              final name = e.key;
              final check = e.value as Map<String, dynamic>;
              final status = check['status'] ?? 'unknown';
              final ms = check['response_time_ms'];
              final msg = check['message'];
              final ok = status == 'ok';
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(children: [
                  Icon(ok ? Icons.check_circle : Icons.error, size: 22,
                      color: ok ? AppColors.success : AppColors.error),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.toUpperCase(), style: AppTypography.labelMedium),
                    if (msg != null)
                      Text(msg.toString(), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                  ])),
                  if (ms != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${ms}ms', style: TextStyle(fontSize: 11, color: AppColors.info, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (ok ? AppColors.success : AppColors.error).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status, style: TextStyle(fontSize: 11,
                        color: ok ? AppColors.success : AppColors.error, fontWeight: FontWeight.w600)),
                  ),
                ]),
              );
            }),

            const SizedBox(height: AppSpacing.lg),
            Center(child: TextButton.icon(
              onPressed: () => s.loadHealth(),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(tr(context, 'gen_retry')),
            )),
          ]),
        ),
      ),
    );
  }
}
