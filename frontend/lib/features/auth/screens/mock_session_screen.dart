// SmartBiz AI — Mock Session Entry Screen.
// Temporary frontend-only auth entry for demo purposes.
// Will be replaced by real Login / Register screens.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/state/app_state.dart';

class MockSessionScreen extends StatelessWidget {
  const MockSessionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.auto_awesome, size: 32, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text('SmartBiz AI', style: AppTypography.headingLarge),
              const SizedBox(height: 6),
              Text(tr(context, 'mock_session_subtitle'),
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
              const SizedBox(height: 40),

              // Owner button
              _SessionButton(
                icon: Icons.business_outlined,
                label: tr(context, 'mock_as_owner'),
                subtitle: tr(context, 'mock_as_owner_sub'),
                color: AppColors.primary,
                onTap: () {
                  context.read<AppState>().signInAsOwner();
                  context.go('/onboarding');
                },
              ),
              const SizedBox(height: 12),

              // Employee button
              _SessionButton(
                icon: Icons.badge_outlined,
                label: tr(context, 'mock_as_employee'),
                subtitle: tr(context, 'mock_as_employee_sub'),
                color: AppColors.info,
                onTap: () {
                  context.read<AppState>().signInAsEmployee();
                  context.go('/dashboard');
                },
              ),
              const SizedBox(height: 12),

              // Super Admin button
              _SessionButton(
                icon: Icons.admin_panel_settings_outlined,
                label: tr(context, 'mock_as_admin'),
                subtitle: tr(context, 'mock_as_admin_sub'),
                color: AppColors.error,
                onTap: () {
                  context.read<AppState>().signInAsSuperAdmin();
                  context.go('/super-admin');
                },
              ),
              const SizedBox(height: 32),

              // Note
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    tr(context, 'mock_session_note'),
                    style: TextStyle(fontSize: 11, color: AppColors.warning.withValues(alpha: 0.9)),
                  )),
                ]),
              ),
            ],
          ),
        ),
      ))),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Session Button
// ═══════════════════════════════════════════════════════════

class _SessionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SessionButton({
    required this.icon, required this.label, required this.subtitle,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTypography.labelMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ])),
            Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.neutral400),
          ]),
        ),
      ),
    );
  }
}
