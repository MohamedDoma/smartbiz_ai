// SmartBiz AI — Generic Page State Widget.
//
// Reusable full-page state widget for empty, disabled, coming soon,
// no permission, and not found states. Centered card layout with
// icon, title, message, and optional action button.
import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';

// ═══════════════════════════════════════════════════════════
//  State Variant
// ═══════════════════════════════════════════════════════════

enum GenericPageStateVariant {
  empty,
  disabled,
  comingSoon,
  noPermission,
  notFound;

  IconData get defaultIcon => switch (this) {
    empty        => Icons.inbox_outlined,
    disabled     => Icons.block_outlined,
    comingSoon   => Icons.rocket_launch_outlined,
    noPermission => Icons.lock_outlined,
    notFound     => Icons.search_off_outlined,
  };

  Color accentColor(BuildContext context) => switch (this) {
    empty        => AppColors.neutral400,
    disabled     => AppColors.warning,
    comingSoon   => AppColors.accent,
    noPermission => AppColors.error,
    notFound     => AppColors.neutral500,
  };

  String get defaultTitleKey => switch (this) {
    empty        => 'gps_empty_title',
    disabled     => 'gps_disabled_title',
    comingSoon   => 'gps_coming_soon_title',
    noPermission => 'gps_no_permission_title',
    notFound     => 'gps_not_found_title',
  };

  String get defaultMessageKey => switch (this) {
    empty        => 'gps_empty_message',
    disabled     => 'gps_disabled_message',
    comingSoon   => 'gps_coming_soon_message',
    noPermission => 'gps_no_permission_message',
    notFound     => 'gps_not_found_message',
  };
}

// ═══════════════════════════════════════════════════════════
//  Widget
// ═══════════════════════════════════════════════════════════

class GenericPageState extends StatelessWidget {
  const GenericPageState({
    super.key,
    required this.variant,
    this.title,
    this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  /// Predefined state variant.
  final GenericPageStateVariant variant;

  /// Override the default title. If null, uses the variant's default l10n key.
  final String? title;

  /// Override the default message. If null, uses the variant's default l10n key.
  final String? message;

  /// Override the default icon.
  final IconData? icon;

  /// Optional action button label (l10n key or raw text).
  final String? actionLabel;

  /// Optional action button callback.
  final VoidCallback? onAction;

  // ── Named constructors for common usage ──────────────────

  const GenericPageState.empty({super.key, this.title, this.message, this.icon, this.actionLabel, this.onAction})
      : variant = GenericPageStateVariant.empty;

  const GenericPageState.disabled({super.key, this.title, this.message, this.icon, this.actionLabel, this.onAction})
      : variant = GenericPageStateVariant.disabled;

  const GenericPageState.comingSoon({super.key, this.title, this.message, this.icon, this.actionLabel, this.onAction})
      : variant = GenericPageStateVariant.comingSoon;

  const GenericPageState.noPermission({super.key, this.title, this.message, this.icon, this.actionLabel, this.onAction})
      : variant = GenericPageStateVariant.noPermission;

  const GenericPageState.notFound({super.key, this.title, this.message, this.icon, this.actionLabel, this.onAction})
      : variant = GenericPageStateVariant.notFound;

  @override
  Widget build(BuildContext context) {
    final resolvedIcon = icon ?? variant.defaultIcon;
    final resolvedTitle = title ?? tr(context, variant.defaultTitleKey);
    final resolvedMessage = message ?? tr(context, variant.defaultMessageKey);
    final color = variant.accentColor(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon ──────────────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(resolvedIcon, size: 36, color: color.withValues(alpha: 0.6)),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Title ─────────────────────────────────────
              Text(
                resolvedTitle,
                style: AppTypography.headingSmall,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.sm),

              // ── Message ───────────────────────────────────
              Text(
                resolvedMessage,
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),

              // ── Action button ─────────────────────────────
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: onAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
