// SmartBiz AI — Dynamic Page Renderer.
//
// Generic skeleton renderer that builds a placeholder UI based on
// DynamicPageDefinition.pageType. Does not replace existing module
// pages — used as a fallback or preview for unimplemented routes.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../dynamic_page_models.dart';
import 'generic_page_state.dart';

// ═══════════════════════════════════════════════════════════
//  Main Renderer
// ═══════════════════════════════════════════════════════════

class DynamicPageRenderer extends StatelessWidget {
  const DynamicPageRenderer({super.key, required this.page});

  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page header ─────────────────────────────
              _PageHeader(page: page),
              const SizedBox(height: AppSpacing.lg),

              // ── Type-specific body ──────────────────────
              Expanded(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) => switch (page.pageType) {
    DynamicPageType.list     => _ListPlaceholder(page: page),
    DynamicPageType.form     => _FormPlaceholder(page: page),
    DynamicPageType.report   => _ReportPlaceholder(page: page),
    DynamicPageType.settings => _SettingsPlaceholder(page: page),
    DynamicPageType.dashboard => _DashboardPlaceholder(page: page),
    DynamicPageType.pos      => const GenericPageState.comingSoon(
      icon: Icons.point_of_sale,
    ),
    DynamicPageType.kanban   => const GenericPageState.comingSoon(
      icon: Icons.view_kanban,
    ),
    DynamicPageType.calendar => const GenericPageState.comingSoon(
      icon: Icons.calendar_month,
    ),
    DynamicPageType.detail   => const GenericPageState.empty(
      icon: Icons.article_outlined,
    ),
    DynamicPageType.empty    => const GenericPageState.empty(),
  };
}

// ═══════════════════════════════════════════════════════════
//  Page Header
// ═══════════════════════════════════════════════════════════

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.page});
  final DynamicPageDefinition page;

  IconData get _typeIcon => switch (page.pageType) {
    DynamicPageType.list      => Icons.list_alt,
    DynamicPageType.form      => Icons.edit_note,
    DynamicPageType.report    => Icons.bar_chart,
    DynamicPageType.settings  => Icons.settings,
    DynamicPageType.dashboard => Icons.dashboard,
    DynamicPageType.pos       => Icons.point_of_sale,
    DynamicPageType.kanban    => Icons.view_kanban,
    DynamicPageType.calendar  => Icons.calendar_month,
    DynamicPageType.detail    => Icons.article_outlined,
    DynamicPageType.empty     => Icons.widgets_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_typeIcon, size: 20, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, page.titleKey),
                style: AppTypography.headingSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                tr(context, page.pageType.labelKey),
                style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        if (page.isAdvancedOnly)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr(context, 'dpr_advanced'),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  List Placeholder
// ═══════════════════════════════════════════════════════════

class _ListPlaceholder extends StatelessWidget {
  const _ListPlaceholder({required this.page});
  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search / filter bar placeholder
        if (page.capabilities.contains(DynamicPageCapability.search) ||
            page.capabilities.contains(DynamicPageCapability.filter))
          DynamicPagePlaceholderCard(
            icon: Icons.search,
            labelKey: 'dpr_search_filter',
            height: 48,
          ),
        const SizedBox(height: AppSpacing.md),
        // Empty list rows
        Expanded(
          child: ListView.separated(
            itemCount: 4,
            separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
            itemBuilder: (_, i) => _ShimmerRow(index: i),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Form Placeholder
// ═══════════════════════════════════════════════════════════

class _FormPlaceholder extends StatelessWidget {
  const _FormPlaceholder({required this.page});
  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < 4; i++) ...[
            _FieldPlaceholder(index: i),
            const SizedBox(height: AppSpacing.base),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Disabled save button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                disabledBackgroundColor: AppColors.neutral200,
              ),
              child: Text(tr(context, 'dpr_save'), style: const TextStyle(color: AppColors.neutral500)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Report Placeholder
// ═══════════════════════════════════════════════════════════

class _ReportPlaceholder extends StatelessWidget {
  const _ReportPlaceholder({required this.page});
  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filters row
        DynamicPagePlaceholderCard(
          icon: Icons.filter_list,
          labelKey: 'dpr_filters',
          height: 48,
        ),
        const SizedBox(height: AppSpacing.base),
        // Chart placeholder
        Expanded(
          flex: 3,
          child: DynamicPagePlaceholderCard(
            icon: Icons.bar_chart,
            labelKey: 'dpr_chart_area',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Table placeholder
        Expanded(
          flex: 2,
          child: DynamicPagePlaceholderCard(
            icon: Icons.table_chart_outlined,
            labelKey: 'dpr_table_area',
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Settings Placeholder
// ═══════════════════════════════════════════════════════════

class _SettingsPlaceholder extends StatelessWidget {
  const _SettingsPlaceholder({required this.page});
  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 5,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.tune, size: 16, color: AppColors.neutral500),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 120 + (i * 15.0), height: 10,
                    decoration: BoxDecoration(color: AppColors.neutral200, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 180 + (i * 10.0), height: 8,
                    decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(4)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.neutral400),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Dashboard Placeholder
// ═══════════════════════════════════════════════════════════

class _DashboardPlaceholder extends StatelessWidget {
  const _DashboardPlaceholder({required this.page});
  final DynamicPageDefinition page;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.md,
      crossAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      children: List.generate(4, (i) => DynamicPagePlaceholderCard(
        icon: [Icons.trending_up, Icons.people, Icons.inventory_2, Icons.receipt_long][i],
        labelKey: 'dpr_widget_placeholder',
      )),
    );
  }
}


// ═══════════════════════════════════════════════════════════
//  Shimmer Row (list item placeholder)
// ═══════════════════════════════════════════════════════════

class _ShimmerRow extends StatelessWidget {
  const _ShimmerRow({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 140 + (index * 20.0), height: 10,
                  decoration: BoxDecoration(color: AppColors.neutral200, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 200 + (index * 10.0), height: 8,
                  decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
          ),
          Container(
            width: 60, height: 10,
            decoration: BoxDecoration(color: AppColors.neutral100, borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Field Placeholder (form input placeholder)
// ═══════════════════════════════════════════════════════════

class _FieldPlaceholder extends StatelessWidget {
  const _FieldPlaceholder({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 80 + (index * 15.0), height: 10,
          decoration: BoxDecoration(color: AppColors.neutral200, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity, height: 44,
          decoration: BoxDecoration(
            color: AppColors.neutral100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.neutral200),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Reusable Placeholder Card
// ═══════════════════════════════════════════════════════════

/// Generic placeholder card with a centered icon and label.
/// Used across multiple page type placeholders.
class DynamicPagePlaceholderCard extends StatelessWidget {
  const DynamicPagePlaceholderCard({
    super.key,
    required this.icon,
    required this.labelKey,
    this.height,
  });

  final IconData icon;
  final String labelKey;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.neutral400),
            const SizedBox(width: AppSpacing.sm),
            Text(
              tr(context, labelKey),
              style: AppTypography.caption.copyWith(color: AppColors.neutral400),
            ),
          ],
        ),
      ),
    );
  }
}
