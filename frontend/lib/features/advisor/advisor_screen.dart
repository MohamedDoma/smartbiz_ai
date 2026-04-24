// SmartBiz AI — AI Advisor screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/responsive.dart';
import 'advisor_state.dart';
import 'models/advisor_models.dart';

class AdvisorScreen extends StatelessWidget {
  const AdvisorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdvisorState>();
    final isMobile = Responsive.isMobile(context);

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.base),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(),
                const SizedBox(height: AppSpacing.lg),
                _SummaryBar(total: state.totalActive, high: state.highImpactCount),
                const SizedBox(height: AppSpacing.lg),
                _StatusTabs(current: state.filterStatus, onChanged: state.setStatusFilter),
                const SizedBox(height: AppSpacing.md),
                _FilterRow(state: state),
                const SizedBox(height: AppSpacing.lg),
                if (state.filtered.isEmpty)
                  _EmptyState(status: state.filterStatus)
                else
                  ...state.filtered.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _RecommendationCard(rec: r, state: state),
                  )),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// ═══════════════════════════════════════════════════════════
//  Header
// ═══════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.accent, AppColors.primary]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.lightbulb, size: 20, color: Colors.white),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(context, 'adv_title'), style: AppTypography.headingLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(tr(context, 'adv_subtitle'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Summary Bar
// ═══════════════════════════════════════════════════════════
class _SummaryBar extends StatelessWidget {
  final int total;
  final int high;
  const _SummaryBar({required this.total, required this.high});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accent.withValues(alpha: 0.08), AppColors.primary.withValues(alpha: 0.05)],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(child: _SummaryItem(labelKey: 'adv_total_active', value: '$total', color: AppColors.primary)),
          Container(width: 1, height: 36, color: AppColors.divider),
          Expanded(child: _SummaryItem(labelKey: 'adv_high_impact', value: '$high', color: AppColors.error)),
          Container(width: 1, height: 36, color: AppColors.divider),
          Expanded(child: _SummaryItem(labelKey: 'adv_confidence', value: '85%', color: AppColors.accent)),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String labelKey;
  final String value;
  final Color color;
  const _SummaryItem({required this.labelKey, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTypography.headingLarge.copyWith(color: color)),
        const SizedBox(height: 2),
        Text(tr(context, labelKey), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Status Tabs
// ═══════════════════════════════════════════════════════════
class _StatusTabs extends StatelessWidget {
  final RecStatus current;
  final void Function(RecStatus) onChanged;
  const _StatusTabs({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: RecStatus.values.map((s) {
          final isSelected = s == current;
          final key = switch (s) {
            RecStatus.active => 'adv_status_active',
            RecStatus.dismissed => 'adv_status_dismissed',
            RecStatus.applied => 'adv_status_applied',
            RecStatus.later => 'adv_status_later',
          };
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
            child: FilterChip(
              label: Text(tr(context, key)),
              selected: isSelected,
              onSelected: (_) => onChanged(s),
              selectedColor: AppColors.primarySurface,
              checkmarkColor: AppColors.primary,
              side: BorderSide(color: isSelected ? AppColors.primary : AppColors.neutral300),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              labelStyle: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Filter Row (impact + category)
// ═══════════════════════════════════════════════════════════
class _FilterRow extends StatelessWidget {
  final AdvisorState state;
  const _FilterRow({required this.state});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Impact
          _FilterChipW(label: tr(context, 'adv_filter_high'), selected: state.filterImpact == RecImpact.high, onTap: () => state.setImpactFilter(RecImpact.high), color: AppColors.error),
          _FilterChipW(label: tr(context, 'adv_filter_medium'), selected: state.filterImpact == RecImpact.medium, onTap: () => state.setImpactFilter(RecImpact.medium), color: AppColors.warning),
          _FilterChipW(label: tr(context, 'adv_filter_low'), selected: state.filterImpact == RecImpact.low, onTap: () => state.setImpactFilter(RecImpact.low), color: AppColors.info),
          Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm), color: AppColors.divider),
          // Categories
          ...RecCategory.values.map((c) {
            final key = switch (c) {
              RecCategory.finance => 'adv_cat_finance',
              RecCategory.inventory => 'adv_cat_inventory',
              RecCategory.sales => 'adv_cat_sales',
              RecCategory.operations => 'adv_cat_ops',
              RecCategory.system => 'adv_cat_system',
            };
            return _FilterChipW(
              label: tr(context, key),
              selected: state.filterCategory == c,
              onTap: () => state.setCategoryFilter(c),
            );
          }),
        ],
      ),
    );
  }
}

class _FilterChipW extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;
  const _FilterChipW({required this.label, required this.selected, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? (color ?? AppColors.primary).withValues(alpha: 0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? (color ?? AppColors.primary) : AppColors.neutral300),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: selected ? (color ?? AppColors.primary) : AppColors.textSecondary)),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Recommendation Card
// ═══════════════════════════════════════════════════════════
class _RecommendationCard extends StatelessWidget {
  final Recommendation rec;
  final AdvisorState state;
  const _RecommendationCard({required this.rec, required this.state});

  Color get _impactColor => switch (rec.impact) {
    RecImpact.high => AppColors.error,
    RecImpact.medium => AppColors.warning,
    RecImpact.low => AppColors.info,
  };

  IconData get _catIcon => switch (rec.category) {
    RecCategory.finance => Icons.account_balance,
    RecCategory.inventory => Icons.inventory_2,
    RecCategory.sales => Icons.trending_up,
    RecCategory.operations => Icons.settings,
    RecCategory.system => Icons.auto_awesome,
  };

  String _impactKey() => switch (rec.impact) {
    RecImpact.high => 'adv_filter_high',
    RecImpact.medium => 'adv_filter_medium',
    RecImpact.low => 'adv_filter_low',
  };

  String _catKey() => switch (rec.category) {
    RecCategory.finance => 'adv_cat_finance',
    RecCategory.inventory => 'adv_cat_inventory',
    RecCategory.sales => 'adv_cat_sales',
    RecCategory.operations => 'adv_cat_ops',
    RecCategory.system => 'adv_cat_system',
  };

  @override
  Widget build(BuildContext context) {
    final isActive = rec.status == RecStatus.active;
    final isApplied = rec.status == RecStatus.applied;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isApplied ? AppColors.success.withValues(alpha: 0.3) : AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + title + badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: _impactColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(_catIcon, size: 18, color: _impactColor),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, rec.titleKey), style: AppTypography.labelLarge),
                    const SizedBox(height: 2),
                    Text(tr(context, rec.descriptionKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Impact badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _impactColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(tr(context, _impactKey()), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _impactColor)),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Category + confidence
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(8)),
                child: Text(tr(context, _catKey()), style: AppTypography.caption.copyWith(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.psychology, size: 12, color: AppColors.accent),
              const SizedBox(width: 2),
              Text('${(rec.confidence * 100).round()}%', style: AppTypography.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (isApplied)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(tr(context, 'adv_status_applied'), style: AppTypography.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
                  ],
                ),
            ],
          ),

          if (isActive) ...[
            const SizedBox(height: AppSpacing.md),
            // Detail text
            Text(tr(context, rec.detailKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: AppSpacing.md),

            // Actions
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => state.apply(rec.id),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(tr(context, 'adv_apply')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _ActionBtn(label: tr(context, 'adv_later'), onTap: () => state.remindLater(rec.id)),
                const SizedBox(width: AppSpacing.sm),
                _ActionBtn(label: tr(context, 'adv_dismiss_btn'), onTap: () => state.dismiss(rec.id)),
              ],
            ),
          ],

          // Reactivate button for non-active
          if (!isActive && !isApplied) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => state.reactivate(rec.id),
              style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: Text(tr(context, 'adv_reactivate')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.neutral300),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Empty State
// ═══════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  final RecStatus status;
  const _EmptyState({required this.status});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.lightbulb_outline, size: 28, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(tr(context, 'adv_empty_title'), style: AppTypography.headingSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            Text(tr(context, 'adv_empty_subtitle'), style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () => context.go('/ai-chat'),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text(tr(context, 'adv_go_chat')),
            ),
          ],
        ),
      ),
    );
  }
}
