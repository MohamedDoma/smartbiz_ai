// SmartBiz AI — Discovery progress bar widget.
//
// Shows adaptive discovery progress based on the backend's completeness
// percentage. No fixed "N / 6" counter — the completeness is dynamic
// and determined by the AI analysis.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';

class DiscoveryProgressBar extends StatelessWidget {
  final double completeness;
  final bool readyForBlueprint;

  const DiscoveryProgressBar({
    super.key,
    required this.completeness,
    this.readyForBlueprint = false,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (completeness / 100).clamp(0.0, 1.0);
    final percentDisplay = completeness.round();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress header
          Row(
            children: [
              const Icon(Icons.explore, size: 16, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(
                tr(context, 'onboard_progress'),
                style: AppTypography.labelSmall,
              ),
              const Spacer(),
              if (readyForBlueprint)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      tr(context, 'disc_q6_ready'),
                      style: AppTypography.labelSmall
                          .copyWith(color: AppColors.success),
                    ),
                  ],
                )
              else
                Text(
                  '$percentDisplay%',
                  style: AppTypography.labelSmall
                      .copyWith(color: AppColors.accent),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 4,
              backgroundColor: AppColors.neutral100,
              valueColor: AlwaysStoppedAnimation<Color>(
                readyForBlueprint ? AppColors.success : AppColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
