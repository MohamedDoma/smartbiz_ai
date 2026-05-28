// SmartBiz AI — Top app bar with localization.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
              onTap: () => context.go('/ai-chat'),
            ),
          ],

          const SizedBox(width: AppSpacing.xs),

          // Notifications
          IconButton(
            onPressed: () => _showNotifications(context),
            icon: Badge(
              smallSize: 8,
              backgroundColor: AppColors.error,
              child: const Icon(Icons.notifications_outlined, color: AppColors.neutral600, size: 22),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),

          const SizedBox(width: AppSpacing.xs),

          // User avatar menu
          PopupMenuButton<String>(
            offset: const Offset(0, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primarySurface,
              child: Text(
                appState.currentUser.fullName.isNotEmpty ? appState.currentUser.fullName[0] : 'U',
                style: const TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(enabled: false, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(appState.currentUser.fullName, style: AppTypography.labelLarge),
                Text(appState.currentUser.email, style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.primarySurface, borderRadius: BorderRadius.circular(6)),
                  child: Text(appState.currentRole.id.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary))),
              ])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'settings', child: Row(children: [const Icon(Icons.settings_outlined, size: 18, color: AppColors.neutral600), const SizedBox(width: 8), Text(tr(context, 'nav_settings'))])),
              PopupMenuItem(value: 'logout', child: Row(children: [const Icon(Icons.logout, size: 18, color: AppColors.error), const SizedBox(width: 8), Text(tr(context, 'ux_logout'), style: const TextStyle(color: AppColors.error))])),
            ],
            onSelected: (v) {
              if (v == 'settings') context.go('/settings');
              if (v == 'logout') ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr(context, 'ux_logout_coming')), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
            },
          ),
        ],
      ),
    );
  }

  void _showNotifications(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        const Icon(Icons.notifications_outlined, size: 20, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(tr(context, 'ux_notifications')),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _NotifTile(icon: Icons.warning_amber, color: AppColors.warning, titleKey: 'ux_notif_stock', subtitleKey: 'ux_notif_stock_desc'),
        _NotifTile(icon: Icons.receipt_long, color: AppColors.primary, titleKey: 'ux_notif_invoice', subtitleKey: 'ux_notif_invoice_desc'),
        _NotifTile(icon: Icons.auto_awesome, color: AppColors.accent, titleKey: 'ux_notif_ai', subtitleKey: 'ux_notif_ai_desc'),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(context, 'ux_close')))],
    ));
  }
}

class _NotifTile extends StatelessWidget {
  final IconData icon; final Color color; final String titleKey; final String subtitleKey;
  const _NotifTile({required this.icon, required this.color, required this.titleKey, required this.subtitleKey});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 16, color: color)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(context, titleKey), style: AppTypography.labelSmall),
        Text(tr(context, subtitleKey), style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
      ])),
    ]),
  );
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
