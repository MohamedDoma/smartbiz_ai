// SmartBiz AI — Platform AI Usage screen (Step 59.1) — real data.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../ai/ai_state.dart';
import '../../../core/api/ai_models.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';

class PlatformUsageScreen extends StatefulWidget {
  const PlatformUsageScreen({super.key});

  @override
  State<PlatformUsageScreen> createState() => _PlatformUsageScreenState();
}

class _PlatformUsageScreenState extends State<PlatformUsageScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AiState>().loadPlatformUsage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AiState>();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Text(tr(context, 'ai_usage'), style: AppTypography.headingSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(tr(context, 'ai_step_59_1_note'),
          style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
        const SizedBox(height: AppSpacing.lg),

        if (s.usageLoading)
          const Center(child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: CircularProgressIndicator(),
          )),

        if (s.usageError != null)
          _errorCard(s),

        if (s.usageSummary != null)
          ..._buildContent(s.usageSummary!),

        if (!s.usageLoading && s.usageSummary == null && s.usageError == null)
          _emptyState(),
      ]),
    );
  }

  Widget _errorCard(AiState s) => Card(
    color: AppColors.error.withValues(alpha: 0.1),
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(tr(context, 'ai_error'), style: AppTypography.bodyMedium.copyWith(color: AppColors.error)),
        const SizedBox(height: AppSpacing.xs),
        Text(s.usageError!, style: AppTypography.caption),
        const SizedBox(height: AppSpacing.sm),
        FilledButton(onPressed: () => s.loadPlatformUsage(), child: Text(tr(context, 'gen_retry'))),
      ]),
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome_outlined, size: 64, color: AppColors.neutral400),
        const SizedBox(height: AppSpacing.md),
        Text(tr(context, 'ai_no_usage_yet'),
          style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center),
      ]),
    ),
  );

  List<Widget> _buildContent(AiUsageSummary u) {
    return [
      // KPI cards
      Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
        _kpi(tr(context, 'ai_total_requests'), u.totalRequests.toString(), Icons.analytics_outlined),
        _kpi(tr(context, 'ai_successful_requests'), u.successfulRequests.toString(), Icons.check_circle_outline),
        _kpi(tr(context, 'ai_failed_requests'), u.failedRequests.toString(), Icons.error_outline),
        _kpi(tr(context, 'ai_total_tokens'), _fmtNum(u.totalTokens), Icons.token_outlined),
        _kpi(tr(context, 'ai_input_tokens'), _fmtNum(u.totalInputTokens), Icons.input_outlined),
        _kpi(tr(context, 'ai_output_tokens'), _fmtNum(u.totalOutputTokens), Icons.output_outlined),
        _kpi(tr(context, 'ai_estimated_cost'), '\$${u.estimatedTotalCost.toStringAsFixed(4)}', Icons.attach_money),
      ]),
      const SizedBox(height: AppSpacing.lg),

      // Budget info
      Card(child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Budget', style: AppTypography.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Text('Monthly: \$${u.budget.monthlyUsd.toStringAsFixed(0)} | Daily limit: ${u.budget.dailyLimit} | Monthly limit: ${u.budget.monthlyLimit}',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
        ]),
      )),
      const SizedBox(height: AppSpacing.lg),

      // By model
      if (u.byModel.isNotEmpty) ...[
        Text(tr(context, 'ai_usage_by_model'), style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        ...u.byModel.map((m) => Card(child: ListTile(
          title: Text(m.model),
          subtitle: Text('${m.requests} requests | ${_fmtNum(m.tokens)} tokens | \$${m.cost.toStringAsFixed(4)}'),
        ))),
        const SizedBox(height: AppSpacing.lg),
      ],

      // By operation
      if (u.byOperation.isNotEmpty) ...[
        Text(tr(context, 'ai_usage_by_operation'), style: AppTypography.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        ...u.byOperation.map((o) => Card(child: ListTile(
          title: Text(o.operation),
          subtitle: Text('${o.requests} requests | ${_fmtNum(o.tokens)} tokens | \$${o.cost.toStringAsFixed(4)}'),
        ))),
        const SizedBox(height: AppSpacing.lg),
      ],

      // Recent errors
      if (u.recentErrors.isNotEmpty) ...[
        Text(tr(context, 'ai_recent_errors'), style: AppTypography.labelLarge.copyWith(color: AppColors.error)),
        const SizedBox(height: AppSpacing.sm),
        ...u.recentErrors.map((e) => Card(
          color: AppColors.error.withValues(alpha: 0.05),
          child: ListTile(
            leading: Icon(Icons.error_outline, color: AppColors.error),
            title: Text(e.errorCode ?? 'unknown'),
            subtitle: Text('${e.errorMessage ?? ''}\n${e.model ?? ''} - ${e.operation ?? ''}',
              style: AppTypography.caption),
          ),
        )),
      ],
    ];
  }

  Widget _kpi(String label, String value, IconData icon) => SizedBox(
    width: 180,
    child: Card(child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: AppTypography.headingSmall),
        Text(label, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ]),
    )),
  );

  String _fmtNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
