/// SmartBiz AI — Top app bar.
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
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
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
      child: Row(
        children: [
          // Menu button on mobile
          if (isMobile && onMenuTap != null)
            IconButton(
              onPressed: onMenuTap,
              icon: const Icon(Icons.menu, color: AppColors.neutral700),
            ),

          // Title
          if (isMobile && onMenuTap != null) const SizedBox(width: AppSpacing.sm),
          Text(title, style: AppTypography.headingMedium),

          const Spacer(),

          // AI shortcut
          _ActionChip(
            icon: Icons.auto_awesome_outlined,
            label: 'AI',
            color: AppColors.accent,
            onTap: () {},
          ),

          const SizedBox(width: AppSpacing.sm),

          // Notifications
          IconButton(
            onPressed: () {},
            icon: Badge(
              smallSize: 8,
              child: const Icon(Icons.notifications_outlined, color: AppColors.neutral600),
            ),
          ),

          const SizedBox(width: AppSpacing.xs),

          // User avatar
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(20),
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primarySurface,
              child: Icon(Icons.person_outline, size: 20, color: AppColors.primary),
            ),
          ),
        ],
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
      color: color.withOpacity(0.1),
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
