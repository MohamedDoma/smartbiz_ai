// SmartBiz AI — Org chart / reporting structure screen (Phase 16.2).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../org_state.dart';
import '../models/org_models.dart';

class OrgChartScreen extends StatelessWidget {
  const OrgChartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OrgState>();
    final isMobile = Responsive.isMobile(context);
    final tree = state.buildOrgTree();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
      child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            IconButton(onPressed: () => context.go('/employees/organization'), icon: const Icon(Icons.arrow_back)),
            const SizedBox(width: AppSpacing.sm),
            Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.account_tree, size: 20, color: Colors.white)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(context, 'org_chart_title'), style: AppTypography.headingLarge),
              Text(tr(context, 'org_chart_subtitle'), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            ])),
          ]),
          const SizedBox(height: AppSpacing.xl),
          _ChartNode(node: tree, depth: 0, state: state, isLast: true),
          const SizedBox(height: AppSpacing.xxl),
        ]),
      )),
    );
  }
}

class _ChartNode extends StatelessWidget {
  final OrgNode node; final int depth; final OrgState state; final bool isLast;
  const _ChartNode({required this.node, required this.depth, required this.state, this.isLast = false});

  Color get _borderColor => depth == 0 ? AppColors.primary : depth == 1 ? AppColors.accent : AppColors.info;
  Color get _bg => _borderColor.withValues(alpha: 0.04);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: EdgeInsetsDirectional.only(start: depth * (isMobile ? 16.0 : 28.0)),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _borderColor.withValues(alpha: 0.25))),
        child: Row(children: [
          if (depth > 0) ...[Container(width: 2, height: 24, color: _borderColor.withValues(alpha: 0.3)), const SizedBox(width: AppSpacing.sm)],
          // Avatar
          Container(width: depth == 0 ? 42 : 36, height: depth == 0 ? 42 : 36,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [_borderColor, _borderColor.withValues(alpha: 0.7)]), borderRadius: BorderRadius.circular(depth == 0 ? 12 : 8)),
            child: Center(child: Text(node.name.isNotEmpty ? node.name[0] : '?', style: TextStyle(fontSize: depth == 0 ? 18 : 14, fontWeight: FontWeight.w700, color: Colors.white)))),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(node.name, style: depth == 0 ? AppTypography.labelLarge : AppTypography.labelMedium),
              if (node.badge != null) ...[
                const SizedBox(width: 6),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                  child: Text(tr(context, node.badge!), style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.warning))),
              ],
            ]),
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: _borderColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Text(state.roleLabel(node.role), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: _borderColor))),
              if (node.title != null) ...[const SizedBox(width: 6), Text(node.title!, style: AppTypography.caption.copyWith(color: AppColors.textSecondary))],
            ]),
          ])),
          if (node.children.isNotEmpty)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(8)),
              child: Text('${node.children.length} ${tr(context, 'org_direct_reports')}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.primary))),
        ]),
      ),
      ...node.children.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: _ChartNode(node: e.value, depth: depth + 1, state: state, isLast: e.key == node.children.length - 1))),
    ]);
  }
}
