// SmartBiz AI — Workspace Branding Card.
//
// Lightweight placeholder showing workspace identity at a glance.
// Reads workspace name and dashboard template from parent props.
// No backend calls, no upload, no persistence — pure presentation.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/dashboard_config_models.dart';
import 'dashboard_widgets.dart' show mapColor;

class WorkspaceBrandingCard extends StatelessWidget {
  const WorkspaceBrandingCard({
    super.key,
    this.workspaceName,
    this.roleName,
    required this.template,
  });

  /// Workspace/org display name. Falls back to a l10n default.
  final String? workspaceName;

  /// Real role display name (localized). Falls back to template label.
  final String? roleName;

  /// Current dashboard template — used for accent preview.
  final DashboardTemplate template;

  @override
  Widget build(BuildContext context) {
    final name = (workspaceName != null && workspaceName!.isNotEmpty)
        ? workspaceName!
        : tr(context, 'ws_brand_default_name');

    final profileLabel = (roleName != null && roleName!.isNotEmpty)
        ? roleName!
        : tr(context, template.labelKey);
    final accentColor = mapColor(template.colorName);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Logo / avatar placeholder ─────────────────
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                _initials(name),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // ── Name + profile label ──────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTypography.labelLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Accent dot
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        profileLabel,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Branding note chip ────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neutral200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.palette_outlined,
                  size: 13,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  tr(context, 'ws_brand_pending'),
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Extracts up to 2 initials from the workspace name.
  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) return '?';
    if (words.length == 1) return words[0].substring(0, words[0].length.clamp(0, 2)).toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }
}
