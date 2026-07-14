// SmartBiz AI — Platform Modules (coming-soon) screen (Step 58.1).
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';

class PlatformModulesScreen extends StatelessWidget {
  const PlatformModulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.extension_outlined, size: 64, color: AppColors.neutral400),
          const SizedBox(height: AppSpacing.md),
          Text(tr(context, 'sa_nav_modules'), style: AppTypography.headingSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tr(context, 'plt_coming_soon'),
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'الوحدات ستتوفر لاحقاً بعد ربط إعدادات الباقات والوحدات.',
            style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
