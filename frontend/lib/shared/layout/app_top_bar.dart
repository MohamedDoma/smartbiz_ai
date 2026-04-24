// SmartBiz AI — Top app bar with localization.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/state/app_state.dart';
import '../../core/responsive.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onMenuTap;

  const AppTopBar({
    super.key,
    required this.title,
    this.onMenuTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final appState = context.watch<AppState>();

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? AppSpacing.sm : AppSpacing.base),
      child: Row(
        children: [
          if (onMenuTap != null) ...[
            IconButton(
              onPressed: onMenuTap,
              icon: const Icon(Icons.menu, color: AppColors.neutral700, size: 22),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],

          Expanded(
            child: Text(
              title,
              style: isMobile ? AppTypography.headingSmall : AppTypography.headingMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),

          const SizedBox(width: AppSpacing.sm),

          // Language toggle
          _LangToggle(
            currentLang: appState.uiLanguage,
            onTap: () {
              final newLang = appState.uiLanguage == AppLanguage.en ? AppLanguage.ar : AppLanguage.en;
              appState.setUiLanguage(newLang);
            },
          ),

          if (!isMobile) ...[
            const SizedBox(width: AppSpacing.sm),
            _ActionChip(
              icon: Icons.auto_awesome_outlined,
              label: tr(context, 'nav_ai_chat'),
              color: AppColors.accent,
              onTap: () {},
            ),
          ],

          const SizedBox(width: AppSpacing.xs),

          IconButton(
            onPressed: () {},
            icon: Badge(
              smallSize: 8,
              backgroundColor: AppColors.error,
              child: const Icon(Icons.notifications_outlined, color: AppColors.neutral600, size: 22),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),

          const SizedBox(width: AppSpacing.xs),

          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(20),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primarySurface,
              child: Text(
                appState.currentUser.fullName.isNotEmpty ? appState.currentUser.fullName[0] : 'U',
                style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LangToggle extends StatelessWidget {
  final AppLanguage currentLang;
  final VoidCallback onTap;

  const _LangToggle({required this.currentLang, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.neutral100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language, size: 14, color: AppColors.neutral600),
              const SizedBox(width: 4),
              Text(
                currentLang == AppLanguage.en ? 'عربي' : 'EN',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.neutral700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
