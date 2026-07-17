// SmartBiz AI — Settings hub with tabs.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../onboarding/onboarding_state.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.base),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(context, 'nav_settings'),
                style: AppTypography.headingLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                tr(context, 'set_subtitle'),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Navigation tiles
              _NavTile(
                icon: Icons.business,
                label: tr(context, 'set_workspace'),
                sub: tr(context, 'set_workspace_sub'),
                color: AppColors.primary,
                onTap: () => context.go('/settings/workspace'),
              ),
              _NavTile(
                icon: Icons.palette,
                label: tr(context, 'set_branding'),
                sub: tr(context, 'set_branding_sub'),
                color: AppColors.accent,
                onTap: () => context.go('/settings/branding'),
              ),
              _NavTile(
                icon: Icons.credit_card,
                label: tr(context, 'set_billing'),
                sub: tr(context, 'set_billing_sub'),
                color: AppColors.success,
                onTap: () => context.go('/settings/billing'),
              ),
              _NavTile(
                icon: Icons.auto_awesome,
                label: tr(context, 'set_ai_usage'),
                sub: tr(context, 'set_ai_usage_sub'),
                color: AppColors.warning,
                onTap: () => context.go('/settings/ai'),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Quick controls (language/role - preserved from original)
              _SectionHeader(title: tr(context, 'settings_language_section')),
              const SizedBox(height: AppSpacing.md),
              _Card(
                children: [
                  _DropdownTile<AppLanguage>(
                    icon: Icons.language,
                    title: tr(context, 'settings_ui_language'),
                    subtitle: appState.uiLanguage.nativeLabel,
                    value: appState.uiLanguage,
                    items: AppLanguage.values
                        .map(
                          (l) => DropdownMenuItem(
                            value: l,
                            child: Text(l.nativeLabel),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) appState.setUiLanguage(v);
                    },
                  ),
                  const Divider(height: 1, indent: 56),
                  _DropdownTile<AppLanguage>(
                    icon: Icons.description_outlined,
                    title: tr(context, 'settings_doc_language'),
                    subtitle: appState.documentLanguage.nativeLabel,
                    value: appState.documentLanguage,
                    items: AppLanguage.values
                        .map(
                          (l) => DropdownMenuItem(
                            value: l,
                            child: Text(l.nativeLabel),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) appState.setDocumentLanguage(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Onboarding reset
              _SectionHeader(title: tr(context, 'settings_onboarding_section')),
              const SizedBox(height: AppSpacing.md),
              _Card(
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.replay,
                        size: 20,
                        color: AppColors.warning,
                      ),
                    ),
                    title: Text(
                      tr(context, 'settings_reset_onboarding'),
                      style: AppTypography.labelLarge,
                    ),
                    subtitle: Text(
                      tr(context, 'settings_reset_onboarding_desc'),
                      style: AppTypography.bodySmall,
                    ),
                    trailing: TextButton(
                      onPressed: () {
                        appState.resetOnboarding();
                        context.read<OnboardingState>().resetOnboarding();
                        context.go('/onboarding');
                      },
                      child: Text(tr(context, 'settings_reset_btn')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.base),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.labelLarge),
                  Text(
                    sub,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: AppColors.neutral400),
          ],
        ),
      ),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) =>
      Text(title, style: AppTypography.headingSmall);
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );
}

class _DropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  const _DropdownTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 20, color: AppColors.primary),
    ),
    title: Text(title, style: AppTypography.labelLarge),
    subtitle: Text(subtitle, style: AppTypography.bodySmall),
    trailing: DropdownButton<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      style: AppTypography.bodyMedium,
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.neutral500),
    ),
  );
}
