// SmartBiz AI — Blueprint preview + provisioning + completion screens.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../models/onboarding_models.dart';
import '../onboarding_state.dart';

class BlueprintScreen extends StatelessWidget {
  const BlueprintScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<OnboardingState>();

    if (state.phase == OnboardingPhase.provisioning || state.phase == OnboardingPhase.complete) {
      return _ProvisioningView(state: state);
    }

    final bp = state.blueprint;
    if (bp == null) return const SizedBox.shrink();

    return _BlueprintPreview(blueprint: bp);
  }
}

// ═══════════════════════════════════════════════════════════
//  Blueprint Preview
// ═══════════════════════════════════════════════════════════
class _BlueprintPreview extends StatelessWidget {
  final BlueprintModel blueprint;
  const _BlueprintPreview({required this.blueprint});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final crossAxisCount = isMobile ? 1 : 2;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  _SectionTitle(icon: Icons.architecture, title: tr(context, 'bp_title'), accent: true),
                  const SizedBox(height: AppSpacing.sm),

                  // Business summary card
                  _BusinessSummaryCard(blueprint: blueprint),
                  const SizedBox(height: AppSpacing.xl),

                  // Required modules
                  _SectionTitle(icon: Icons.check_circle_outline, title: tr(context, 'bp_required_modules')),
                  const SizedBox(height: AppSpacing.md),
                  _ModuleGrid(modules: blueprint.requiredModules, crossAxisCount: crossAxisCount),
                  const SizedBox(height: AppSpacing.xl),

                  // Optional modules
                  if (blueprint.optionalModules.isNotEmpty) ...[
                    _SectionTitle(icon: Icons.add_circle_outline, title: tr(context, 'bp_optional_modules')),
                    const SizedBox(height: AppSpacing.md),
                    _ModuleGrid(modules: blueprint.optionalModules, crossAxisCount: crossAxisCount, optional: true),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Suggested roles
                  _SectionTitle(icon: Icons.badge_outlined, title: tr(context, 'bp_suggested_roles')),
                  const SizedBox(height: AppSpacing.md),
                  ...blueprint.suggestedRoles.map((r) => _RoleCard(role: r)),
                  const SizedBox(height: AppSpacing.xl),

                  // Workflows
                  _SectionTitle(icon: Icons.account_tree_outlined, title: tr(context, 'bp_workflows')),
                  const SizedBox(height: AppSpacing.md),
                  _StringListCard(keys: blueprint.suggestedWorkflows),
                  const SizedBox(height: AppSpacing.xl),

                  // Dashboards
                  _SectionTitle(icon: Icons.dashboard_outlined, title: tr(context, 'bp_dashboards')),
                  const SizedBox(height: AppSpacing.md),
                  _StringListCard(keys: blueprint.suggestedDashboards),
                  const SizedBox(height: AppSpacing.xl),

                  // Automations
                  _SectionTitle(icon: Icons.bolt, title: tr(context, 'bp_automations')),
                  const SizedBox(height: AppSpacing.md),
                  _StringListCard(keys: blueprint.suggestedAutomations),
                  const SizedBox(height: AppSpacing.xl),

                  // Role previews ("What Your Team Gets")
                  _SectionTitle(icon: Icons.groups_outlined, title: tr(context, 'rp_title')),
                  const SizedBox(height: AppSpacing.md),
                  _RolePreviewGrid(isMobile: isMobile),
                  const SizedBox(height: AppSpacing.xl),

                  // Notes
                  if (blueprint.notes.isNotEmpty) ...[
                    _SectionTitle(icon: Icons.info_outline, title: tr(context, 'bp_notes')),
                    const SizedBox(height: AppSpacing.md),
                    _StringListCard(keys: blueprint.notes, infoStyle: true),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  const SizedBox(height: AppSpacing.base),
                ],
              ),
            ),
          ),
        ),

        // Bottom action bar
        _BlueprintActions(),
      ],
    );
  }
}

class _BusinessSummaryCard extends StatelessWidget {
  final BlueprintModel blueprint;
  const _BusinessSummaryCard({required this.blueprint});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.business, size: 22, color: Colors.white),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(blueprint.businessName, style: AppTypography.headingSmall),
                      const SizedBox(height: 2),
                      Text('${tr(context, 'bp_business_type')}: ${blueprint.businessType}',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.accent)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(blueprint.businessDescription, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool accent;
  const _SectionTitle({required this.icon, required this.title, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: accent ? AppColors.accent : AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: accent ? AppTypography.headingMedium : AppTypography.headingSmall),
      ],
    );
  }
}

// ── Module grid ─────────────────────────────────────────────
class _ModuleGrid extends StatelessWidget {
  final List<BlueprintModule> modules;
  final int crossAxisCount;
  final bool optional;
  const _ModuleGrid({required this.modules, required this.crossAxisCount, this.optional = false});

  static const _iconMap = <String, IconData>{
    'point_of_sale': Icons.point_of_sale,
    'inventory_2': Icons.inventory_2,
    'warehouse': Icons.warehouse,
    'people': Icons.people,
    'account_balance': Icons.account_balance,
    'bar_chart': Icons.bar_chart,
    'badge': Icons.badge,
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: modules.map((m) {
        final iconData = _iconMap[m.icon] ?? Icons.extension;
        return SizedBox(
          width: crossAxisCount == 1 ? double.infinity : 380,
          child: Card(
            color: optional ? AppColors.neutral50 : null,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: optional ? AppColors.neutral100 : AppColors.primarySurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(iconData, size: 20, color: optional ? AppColors.neutral500 : AppColors.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(context, m.nameKey), style: AppTypography.labelLarge),
                        const SizedBox(height: 2),
                        Text(tr(context, m.descriptionKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (!optional)
                    const Icon(Icons.check_circle, size: 18, color: AppColors.success),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Role card ───────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final BlueprintRole role;
  const _RoleCard({required this.role});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.accentSurface, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.person, size: 20, color: AppColors.accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(context, role.nameKey), style: AppTypography.labelLarge),
                    const SizedBox(height: 2),
                    Text(tr(context, role.descriptionKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Chip(
                label: Text('${role.accessModules.length} ${tr(context, 'bp_role_access')}',
                    style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                backgroundColor: AppColors.primarySurface,
                side: BorderSide.none,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── String list card ────────────────────────────────────────
class _StringListCard extends StatelessWidget {
  final List<String> keys;
  final bool infoStyle;
  const _StringListCard({required this.keys, this.infoStyle = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: infoStyle ? AppColors.infoSurface : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: keys.map((key) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  infoStyle ? Icons.info_outline : Icons.chevron_right,
                  size: 16,
                  color: infoStyle ? AppColors.info : AppColors.accent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(tr(context, key), style: AppTypography.bodyMedium)),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }
}

// ── Role preview grid ───────────────────────────────────────
class _RolePreviewGrid extends StatelessWidget {
  final bool isMobile;
  const _RolePreviewGrid({required this.isMobile});

  @override
  Widget build(BuildContext context) {
    final roles = [
      _RolePreviewData(Icons.admin_panel_settings, 'bp_role_owner', 'rp_owner_preview', AppColors.primary),
      _RolePreviewData(Icons.point_of_sale, 'bp_role_cashier', 'rp_cashier_preview', AppColors.accent),
      _RolePreviewData(Icons.warehouse, 'bp_role_warehouse', 'rp_warehouse_preview', AppColors.warning),
      _RolePreviewData(Icons.account_balance, 'bp_role_accountant', 'rp_accountant_preview', AppColors.info),
    ];

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: roles.map((r) => SizedBox(
        width: isMobile ? double.infinity : 380,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: r.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(r.icon, size: 22, color: r.color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(context, r.nameKey), style: AppTypography.labelLarge),
                      const SizedBox(height: 2),
                      Text(tr(context, r.previewKey), style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      )).toList(),
    );
  }
}

class _RolePreviewData {
  final IconData icon;
  final String nameKey;
  final String previewKey;
  final Color color;
  const _RolePreviewData(this.icon, this.nameKey, this.previewKey, this.color);
}

// ── Blueprint bottom actions ────────────────────────────────
class _BlueprintActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.read<OnboardingState>().goBack(),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(tr(context, 'bp_refine')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => context.read<OnboardingState>().startProvisioning(),
                icon: const Icon(Icons.rocket_launch, size: 16),
                label: Text(tr(context, 'bp_accept')),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Provisioning / Completion View
// ═══════════════════════════════════════════════════════════
class _ProvisioningView extends StatelessWidget {
  final OnboardingState state;
  const _ProvisioningView({required this.state});

  @override
  Widget build(BuildContext context) {
    final isDone = state.provisioningDone;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDone ? AppColors.successSurface : AppColors.primarySurface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDone ? Icons.check_circle : Icons.settings,
                  size: 40,
                  color: isDone ? AppColors.success : AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              Text(
                tr(context, isDone ? 'prov_success_title' : 'prov_title'),
                style: AppTypography.headingLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),

              Text(
                tr(context, isDone ? 'prov_success_subtitle' : 'prov_in_progress'),
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),

              if (!isDone)
                const SizedBox(width: 200, child: LinearProgressIndicator()),

              if (isDone) ...[
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: () {
                      context.read<AppState>().completeOnboarding();
                      context.go('/dashboard');
                    },
                    icon: const Icon(Icons.dashboard, size: 18),
                    label: Text(tr(context, 'prov_go_to_dashboard')),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
