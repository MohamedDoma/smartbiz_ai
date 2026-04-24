// SmartBiz AI — Settings screen with demo controls.
//
// Allows switching: UI language, document language, role.
// For dev/demo verification of localization + role context.
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Language & Region ──────────────────────────
            _SectionHeader(title: tr(context, 'settings_language_section')),
            const SizedBox(height: AppSpacing.md),

            _SettingsCard(children: [
              _DropdownTile<AppLanguage>(
                icon: Icons.language,
                title: tr(context, 'settings_ui_language'),
                subtitle: appState.uiLanguage.nativeLabel,
                value: appState.uiLanguage,
                items: AppLanguage.values.map((l) => DropdownMenuItem(
                  value: l,
                  child: Text(l.nativeLabel),
                )).toList(),
                onChanged: (lang) {
                  if (lang != null) appState.setUiLanguage(lang);
                },
              ),
              const Divider(height: 1, indent: 56),
              _DropdownTile<AppLanguage>(
                icon: Icons.description_outlined,
                title: tr(context, 'settings_doc_language'),
                subtitle: appState.documentLanguage.nativeLabel,
                value: appState.documentLanguage,
                items: AppLanguage.values.map((l) => DropdownMenuItem(
                  value: l,
                  child: Text(l.nativeLabel),
                )).toList(),
                onChanged: (lang) {
                  if (lang != null) appState.setDocumentLanguage(lang);
                },
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // ── Role & Access ─────────────────────────────
            _SectionHeader(title: tr(context, 'settings_role_section')),
            const SizedBox(height: AppSpacing.md),

            _SettingsCard(children: [
              _DropdownTile<AppRole>(
                icon: Icons.badge_outlined,
                title: tr(context, 'settings_role'),
                subtitle: appState.currentRole.label(appState.uiLanguage),
                value: appState.currentRole,
                items: AppRole.values.map((r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.label(appState.uiLanguage)),
                )).toList(),
                onChanged: (role) {
                  if (role != null) appState.setRole(role);
                },
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // ── Workspace Info ─────────────────────────────
            _SectionHeader(title: tr(context, 'settings_workspace')),
            const SizedBox(height: AppSpacing.md),

            _SettingsCard(children: [
              _InfoTile(
                icon: Icons.business,
                title: tr(context, 'settings_workspace'),
                value: appState.currentWorkspace.name,
              ),
              const Divider(height: 1, indent: 56),
              _InfoTile(
                icon: Icons.person,
                title: appState.currentUser.fullName,
                value: appState.currentUser.email,
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // ── Demo Controls ──────────────────────────────
            _SectionHeader(title: tr(context, 'settings_demo_controls')),
            const SizedBox(height: AppSpacing.md),

            _SettingsCard(children: [
              _InfoTile(
                icon: Icons.translate,
                title: 'UI Direction',
                value: appState.isRtl ? 'RTL (Arabic)' : 'LTR (English)',
              ),
              const Divider(height: 1, indent: 56),
              _InfoTile(
                icon: Icons.description,
                title: 'Doc Language',
                value: '${appState.documentLanguage.label} (${appState.documentLanguage.nativeLabel})',
              ),
              const Divider(height: 1, indent: 56),
              _InfoTile(
                icon: Icons.security,
                title: 'Nav items visible',
                value: '${_countVisibleItems(appState)} items',
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),

            // ── Onboarding Reset ────────────────────────────
            _SectionHeader(title: tr(context, 'settings_onboarding_section')),
            const SizedBox(height: AppSpacing.md),

            _SettingsCard(children: [
              _InfoTile(
                icon: Icons.rocket_launch,
                title: tr(context, 'settings_onboarding_status'),
                value: appState.isOnboardingCompleted
                    ? tr(context, 'settings_onboarding_completed')
                    : tr(context, 'settings_onboarding_pending'),
              ),
              const Divider(height: 1, indent: 56),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.warningLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.replay, size: 20, color: AppColors.warning),
                ),
                title: Text(tr(context, 'settings_reset_onboarding'), style: AppTypography.labelLarge),
                subtitle: Text(tr(context, 'settings_reset_onboarding_desc'), style: AppTypography.bodySmall),
                trailing: TextButton(
                  onPressed: () {
                    appState.resetOnboarding();
                    context.read<OnboardingState>().resetOnboarding();
                    context.go('/onboarding');
                  },
                  child: Text(tr(context, 'settings_reset_btn')),
                ),
              ),
            ]),

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  int _countVisibleItems(AppState appState) {
    int count = 0;
    for (final section in const [
      ['dashboard', 'ai_chat', 'advisor'],
      ['sales', 'products', 'inventory', 'customers'],
      ['accounting', 'reports'],
      ['employees', 'settings'],
    ]) {
      for (final id in section) {
        if (appState.currentRole.canSee(id)) count++;
      }
    }
    if (appState.isSuperAdmin) count++;
    return count;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: AppTypography.headingSmall);
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return ListTile(
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
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({required this.icon, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 20, color: AppColors.neutral600),
      ),
      title: Text(title, style: AppTypography.labelLarge),
      subtitle: Text(value, style: AppTypography.bodySmall),
    );
  }
}
