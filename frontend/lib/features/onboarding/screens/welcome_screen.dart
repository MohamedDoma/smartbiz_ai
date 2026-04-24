// SmartBiz AI — Owner onboarding welcome screen.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/state/app_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../onboarding_state.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final appState = context.watch<AppState>();
    final isArabic = appState.uiLanguage == AppLanguage.ar;

    return Stack(
      children: [
        // Main content
        Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? AppSpacing.base : AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo + gradient orb
                  _AnimatedOrb(),
                  const SizedBox(height: AppSpacing.xxl),

                  // Title
                  Text(
                    tr(context, 'onboard_welcome_title'),
                    style: isMobile ? AppTypography.headingLarge : AppTypography.displaySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Subtitle
                  Text(
                    tr(context, 'onboard_welcome_subtitle'),
                    style: AppTypography.bodyLarge.copyWith(color: AppColors.textSecondary, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xxl),

                  // Feature highlights
                  _FeatureRow(icon: Icons.auto_awesome, text: tr(context, 'app_tagline')),
                  const SizedBox(height: AppSpacing.md),
                  _FeatureRow(icon: Icons.speed, text: tr(context, 'onboard_generating').replaceAll('...', '')),
                  const SizedBox(height: AppSpacing.md),
                  _FeatureRow(icon: Icons.security, text: tr(context, 'bp_role_owner_desc')),
                  const SizedBox(height: AppSpacing.xxl + AppSpacing.base),

                  // CTA button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: () {
                        context.read<OnboardingState>().startDiscovery(context);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: AppTypography.labelLarge.copyWith(fontSize: 16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr(context, 'onboard_start')),
                          const SizedBox(width: AppSpacing.sm),
                          const Icon(Icons.arrow_forward, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ),

        // Language toggle — top end corner (RTL-aware)
        PositionedDirectional(
          top: AppSpacing.sm,
          end: AppSpacing.md,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                appState.setUiLanguage(isArabic ? AppLanguage.en : AppLanguage.ar);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.neutral300),
                  color: AppColors.surface,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      isArabic ? 'English' : 'عربي',
                      style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedOrb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          colors: [AppColors.accent, AppColors.primary, Color(0xFF1A1A2E)],
          stops: [0.0, 0.5, 1.0],
          radius: 0.8,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: 10),
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.2), blurRadius: 60, spreadRadius: 20),
        ],
      ),
      child: const Center(
        child: Icon(Icons.auto_awesome, size: 40, color: Colors.white),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primarySurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(text, style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
