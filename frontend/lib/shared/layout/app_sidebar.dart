// SmartBiz AI — Left sidebar with localization + role filtering.
// Supports dynamic blueprint navigation via BlueprintNavigationController
// with safe fallback to the legacy hardcoded navigation model.
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
import '../../core/modules/blueprint_navigation_controller.dart';
import '../../core/modules/module_navigation_resolver.dart' as nav;
import '../../core/modules/workspace_module_state.dart';

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
    // Only rebuild when role or superAdmin status changes
    final appState = context.read<AppState>();
    // Select only the fields we actually depend on for nav filtering
    context.select<AppState, String>((s) => s.currentRole.id);
    context.select<AppState, bool>((s) => s.isSuperAdmin);
    context.select<AppState, AppLanguage>((s) => s.uiLanguage);
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
        if (expanded)
          _buildWorkspaceContext(context),
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
                      context.read<AppState>().displayRoleName(context.read<AppState>().uiLanguage),
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

  // ═══════════════════════════════════════════════════════════
  //  Navigation item source resolution
  // ═══════════════════════════════════════════════════════════

  /// Returns the list of NavItem tiles to render.
  /// Uses dynamic blueprint items when the controller is ready;
  /// falls back to the legacy hardcoded sections otherwise.
  List<Widget> _buildNavItems(BuildContext context, ShellState shell, AppState appState, bool expanded) {
    // Narrow selector: only rebuild when the nav item list changes.
    final navCtrl = context.watch<BlueprintNavigationController>();
    final useDynamic = !navCtrl.useFallbackNavigation;

    if (useDynamic) {
      return _buildDynamicNavItems(context, shell, appState, navCtrl, expanded);
    }
    return _buildLegacyNavItems(context, shell, appState, expanded);
  }

  // ─── Dynamic (blueprint-driven) navigation ───────────────

  List<Widget> _buildDynamicNavItems(
    BuildContext context,
    ShellState shell,
    AppState appState,
    BlueprintNavigationController navCtrl,
    bool expanded,
  ) {
    final dynamicItems = navCtrl.navItems;

    // Dynamic items use direct positional indices (0, 1, 2, …).
    // AppShell._flatItems() returns the same list, so indices align.
    final widgets = <Widget>[];
    for (int i = 0; i < dynamicItems.length; i++) {
      final item = dynamicItems[i];
      widgets.add(_NavTile(
        label: tr(context, item.labelKey),
        icon: item.icon,
        selected: shell.selectedIndex == i,
        expanded: expanded,
        onTap: () => onItemTap(i),
      ));
    }

    // Super admin section (appended after dynamic items).
    _appendSuperAdminItems(
      widgets, context, shell, appState, expanded,
      dynamicItems.length, // offset for super admin indices
    );

    return widgets;
  }

  // ─── Legacy (hardcoded) navigation ───────────────────────

  List<Widget> _buildLegacyNavItems(BuildContext context, ShellState shell, AppState appState, bool expanded) {
    final items = <Widget>[];
    int flatIndex = 0;

    for (final section in appNavigation) {
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

  // ─── Helpers ─────────────────────────────────────────────

  /// Appends the super admin section if the current user is a super admin.
  /// [indexOffset] is the starting flat index for admin items.
  void _appendSuperAdminItems(
    List<Widget> widgets,
    BuildContext context,
    ShellState shell,
    AppState appState,
    bool expanded,
    int indexOffset,
  ) {
    if (!appState.isSuperAdmin) return;
    if (expanded) {
      widgets.add(const Divider(indent: 16, endIndent: 16));
      widgets.add(Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xs),
        child: Text(tr(context, superAdminNav.titleKey).toUpperCase(), style: AppTypography.labelSmall.copyWith(color: AppColors.warning)),
      ));
    }
    int idx = indexOffset;
    for (final item in superAdminNav.items) {
      final index = idx;
      widgets.add(_NavTile(
        label: tr(context, item.labelKey),
        icon: item.icon,
        selected: shell.selectedIndex == index,
        expanded: expanded,
        onTap: () => onItemTap(index),
      ));
      idx++;
    }
  }

  // ── Workspace Context Footer ───────────────────────────

  /// Displays workspace name, navigation mode toggle, and demo indicator
  /// at the bottom of the sidebar when expanded.
  Widget _buildWorkspaceContext(BuildContext context) {
    final appState = context.read<AppState>();
    final navCtrl = context.watch<BlueprintNavigationController>();
    final moduleState = context.watch<WorkspaceModuleState>();

    // Workspace name: use real data, fall back to l10n default.
    final wsName = appState.currentWorkspace.name.isNotEmpty
        ? appState.currentWorkspace.name
        : tr(context, 'ws_shell_default_name');

    // Demo indicator: shown when workspace ID starts with 'demo'.
    final isDemo = appState.currentWorkspace.id.startsWith('demo');

    // Setup indicator: shown when no real AI/backend blueprint applied.
    final needsSetup = !moduleState.blueprintApplied;

    // Advanced empty state: user switched to Advanced but the workspace
    // has no enabled advanced-only modules.
    final showAdvancedHint = navCtrl.mode == nav.NavigationMode.advanced
        && !navCtrl.useFallbackNavigation
        && !navCtrl.hasAdvancedOnlyItems;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm + 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Workspace name
          Row(
            children: [
              Icon(Icons.workspaces_outlined, size: 14, color: AppColors.neutral400),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  wsName,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.neutral600,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          // Mode toggle + status badges
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _WorkspaceModeToggle(
                currentMode: navCtrl.mode,
                onModeChanged: (mode) => navCtrl.setMode(mode),
              ),
              if (isDemo)
                _WorkspaceModeBadge(
                  label: tr(context, 'ws_shell_demo'),
                  color: AppColors.warning,
                ),
              if (needsSetup)
                _WorkspaceModeBadge(
                  label: tr(context, 'ws_shell_setup_needed'),
                  color: AppColors.info,
                ),
            ],
          ),
          // Advanced mode empty state
          if (showAdvancedHint) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.info_outline, size: 11, color: AppColors.neutral400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    tr(context, 'ws_shell_no_advanced'),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.neutral400,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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

/// Compact segmented toggle for Basic / Advanced navigation mode.
class _WorkspaceModeToggle extends StatelessWidget {
  final nav.NavigationMode currentMode;
  final ValueChanged<nav.NavigationMode> onModeChanged;

  const _WorkspaceModeToggle({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider, width: 0.5),
      ),
      padding: const EdgeInsets.all(1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeSegment(
            label: tr(context, 'ws_shell_mode_basic'),
            isSelected: currentMode == nav.NavigationMode.basic,
            color: AppColors.success,
            onTap: () => onModeChanged(nav.NavigationMode.basic),
          ),
          _ModeSegment(
            label: tr(context, 'ws_shell_mode_advanced'),
            isSelected: currentMode == nav.NavigationMode.advanced,
            color: AppColors.accent,
            onTap: () => onModeChanged(nav.NavigationMode.advanced),
          ),
        ],
      ),
    );
  }
}

/// One segment of the mode toggle.
class _ModeSegment extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _ModeSegment({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: color.withValues(alpha: 0.3), width: 0.5)
              : Border.all(color: Colors.transparent, width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? color : AppColors.neutral400,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Small colored pill badge for workspace status indicators (e.g. Demo).
class _WorkspaceModeBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _WorkspaceModeBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
