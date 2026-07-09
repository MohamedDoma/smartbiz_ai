// SmartBiz AI — Platform AI Usage (coming-soon) screen (Step 58.1).
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';

class PlatformUsageScreen extends StatelessWidget {
  const PlatformUsageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_outlined, size: 64, color: AppColors.neutral400),
          const SizedBox(height: AppSpacing.md),
          Text(tr(context, 'sa_nav_usage'), style: AppTypography.headingSmall),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'سيظهر استخدام الذكاء بعد تفعيل AI في Step 59',
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'AI usage metrics will appear after AI is enabled in Step 59',
            style: AppTypography.caption.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}
