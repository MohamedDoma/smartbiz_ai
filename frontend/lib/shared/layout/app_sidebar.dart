// SmartBiz AI — Left sidebar with localization + role filtering.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/navigation/nav_model.dart';
import '../../core/navigation/shell_state.dart';
import '../../core/state/app_state.dart';
import '../../core/responsive.dart';

class AppSidebar extends StatelessWidget {
  final void Function(int index) onItemTap;
  final bool forceExpanded;

  const AppSidebar({
    super.key,
    required this.onItemTap,
    this.forceExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellState>();
    final appState = context.watch<AppState>();
    final isInDrawer = forceExpanded;
    final expanded = isInDrawer || (shell.sidebarExpanded && Responsive.isDesktop(context));
    final width = isInDrawer ? double.infinity : (expanded ? Responsive.sidebarWidth : Responsive.sidebarCollapsed);

    final content = Column(
      children: [
        _buildHeader(context, expanded),
        const Divider(height: 1, color: AppColors.divider),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: _buildNavItems(context, shell, appState, expanded),
          ),
        ),
        if (!isInDrawer && Responsive.isDesktop(context))
          _buildCollapseToggle(context, expanded),
      ],
    );

    if (isInDrawer) return content;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context, bool expanded) {
    return SizedBox(
      height: 64,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: expanded ? AppSpacing.base : AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('S', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            if (expanded) ...[
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(tr(context, 'app_name'), style: AppTypography.headingSmall, overflow: TextOverflow.ellipsis),
                    Text(
                      context.read<AppState>().currentRole.label(context.read<AppState>().uiLanguage),
                      style: AppTypography.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNavItems(BuildContext context, ShellState shell, AppState appState, bool expanded) {
    final items = <Widget>[];
    int flatIndex = 0;

    for (final section in appNavigation) {
      // Collect visible items in this section
      final visibleItems = section.items.where((item) => appState.currentRole.canSee(item.id)).toList();
      if (visibleItems.isEmpty) continue;

      if (expanded) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.xs),
          child: Text(tr(context, section.titleKey).toUpperCase(), style: AppTypography.labelSmall),
        ));
      } else {
        items.add(const SizedBox(height: AppSpacing.md));
      }

      for (final item in visibleItems) {
        final index = flatIndex;
        items.add(_NavTile(
          label: tr(context, item.labelKey),
          icon: item.icon,
          selected: shell.selectedIndex == index,
          expanded: expanded,
          onTap: () => onItemTap(index),
        ));
        flatIndex++;
      }
    }

    // Super admin section
    if (appState.isSuperAdmin) {
      if (expanded) {
        items.add(const Divider(indent: 16, endIndent: 16));
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xs),
          child: Text(tr(context, superAdminNav.titleKey).toUpperCase(), style: AppTypography.labelSmall.copyWith(color: AppColors.warning)),
        ));
      }
      for (final item in superAdminNav.items) {
        items.add(_NavTile(
          label: tr(context, item.labelKey),
          icon: item.icon,
          selected: shell.selectedIndex == flatIndex,
          expanded: expanded,
          onTap: () => onItemTap(flatIndex),
        ));
        flatIndex++;
      }
    }

    return items;
  }

  Widget _buildCollapseToggle(BuildContext context, bool expanded) {
    return InkWell(
      onTap: () => context.read<ShellState>().toggleSidebar(),
      child: Container(
        height: 48,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Center(
          child: Icon(
            expanded ? Icons.chevron_left : Icons.chevron_right,
            color: AppColors.neutral500,
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _NavTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = selected ? AppColors.primarySurface : Colors.transparent;
    final iconColor = selected ? AppColors.primary : AppColors.neutral500;
    final textColor = selected ? AppColors.primary : AppColors.neutral700;
    final fontWeight = selected ? FontWeight.w600 : FontWeight.w500;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? AppSpacing.sm : AppSpacing.xs,
        vertical: 1,
      ),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          splashColor: AppColors.primary.withValues(alpha: 0.08),
          highlightColor: AppColors.primary.withValues(alpha: 0.05),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? AppSpacing.md : 0,
              vertical: AppSpacing.sm + 2,
            ),
            child: expanded
                ? Row(
                    children: [
                      Icon(icon, size: 20, color: iconColor),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(label, style: AppTypography.labelLarge.copyWith(color: textColor, fontWeight: fontWeight), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  )
                : Center(
                    child: Tooltip(
                      message: label,
                      child: Icon(icon, size: 22, color: iconColor),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
