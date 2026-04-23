/// SmartBiz AI — Left sidebar for desktop/tablet.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/navigation/nav_model.dart';
import '../../core/navigation/shell_state.dart';
import '../../core/responsive.dart';

class AppSidebar extends StatelessWidget {
  final void Function(int index) onItemTap;

  const AppSidebar({super.key, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellState>();
    final expanded = shell.sidebarExpanded && Responsive.isDesktop(context);
    final width = expanded ? Responsive.sidebarWidth : Responsive.sidebarCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        children: [
          // Logo / Brand
          _buildHeader(expanded),
          const Divider(height: 1, color: AppColors.divider),

          // Navigation
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: _buildNavItems(context, shell, expanded),
            ),
          ),

          // Collapse toggle (desktop only)
          if (Responsive.isDesktop(context))
            _buildCollapseToggle(context, expanded),
        ],
      ),
    );
  }

  Widget _buildHeader(bool expanded) {
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
                    Text('SmartBiz', style: AppTypography.headingSmall),
                    Text('AI', style: AppTypography.caption.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600, letterSpacing: 1)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNavItems(BuildContext context, ShellState shell, bool expanded) {
    final items = <Widget>[];
    int flatIndex = 0;

    for (final section in appNavigation) {
      // Section header
      if (expanded) {
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.xs),
          child: Text(section.title.toUpperCase(), style: AppTypography.labelSmall),
        ));
      } else {
        items.add(const SizedBox(height: AppSpacing.md));
      }

      for (final item in section.items) {
        final index = flatIndex;
        final selected = shell.selectedIndex == index;

        items.add(_NavTile(
          item: item,
          selected: selected,
          expanded: expanded,
          onTap: () => onItemTap(index),
        ));

        flatIndex++;
      }
    }

    // Super admin section
    if (shell.isSuperAdmin) {
      if (expanded) {
        items.add(const Divider(indent: 16, endIndent: 16));
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xs),
          child: Text(superAdminNav.title.toUpperCase(), style: AppTypography.labelSmall.copyWith(color: AppColors.warning)),
        ));
      }
      for (final item in superAdminNav.items) {
        final index = flatIndex;
        items.add(_NavTile(
          item: item,
          selected: shell.selectedIndex == index,
          expanded: expanded,
          onTap: () => onItemTap(index),
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
  final NavItem item;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? AppSpacing.sm : AppSpacing.xs,
        vertical: 1,
      ),
      child: Material(
        color: selected ? AppColors.primarySurface : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.sm),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: expanded ? AppSpacing.md : 0,
              vertical: AppSpacing.sm + 2,
            ),
            child: expanded
                ? Row(
                    children: [
                      Icon(item.icon, size: 20, color: selected ? AppColors.primary : AppColors.neutral500),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          item.label,
                          style: AppTypography.labelLarge.copyWith(
                            color: selected ? AppColors.primary : AppColors.neutral700,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Tooltip(
                      message: item.label,
                      child: Icon(item.icon, size: 22, color: selected ? AppColors.primary : AppColors.neutral500),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
