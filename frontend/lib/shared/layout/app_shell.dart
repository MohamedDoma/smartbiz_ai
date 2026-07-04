// SmartBiz AI — Main responsive app shell with role filtering + localization.
// Supports dynamic blueprint navigation via BlueprintNavigationController
// with safe fallback to the legacy hardcoded navigation model.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/nav_model.dart';
import '../../core/navigation/shell_state.dart';
import '../../core/state/app_state.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/modules/blueprint_navigation_controller.dart';
import 'app_sidebar.dart';
import 'app_top_bar.dart';

class AppShell extends StatefulWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ═══════════════════════════════════════════════════════════
  //  Flat navigation item list
  // ═══════════════════════════════════════════════════════════

  /// Returns the flat list of nav items used for index-based navigation.
  ///
  /// Uses dynamic items from BlueprintNavigationController when available;
  /// falls back to the legacy role-filtered appNavigation otherwise.
  /// Super admin items are appended at the end in both modes.
  List<NavItem> _flatItems(BuildContext context) {
    final navCtrl = context.read<BlueprintNavigationController>();
    final appState = context.read<AppState>();

    List<NavItem> items;
    if (!navCtrl.useFallbackNavigation) {
      // Dynamic mode: use blueprint-resolved items.
      items = List.of(navCtrl.navItems);
    } else {
      // Legacy fallback: flatten appNavigation with role filtering.
      items = <NavItem>[];
      for (final section in appNavigation) {
        for (final item in section.items) {
          if (appState.currentRole.canSee(item.id)) {
            items.add(item);
          }
        }
      }
    }

    // Super admin items are always appended at the tail.
    if (appState.isSuperAdmin) {
      items.addAll(superAdminNav.items);
    }
    return items;
  }

  String _currentTitle(BuildContext context) {
    final shell = context.watch<ShellState>();
    final items = _flatItems(context);
    if (shell.selectedIndex < items.length) {
      return tr(context, items[shell.selectedIndex].labelKey);
    }
    return tr(context, 'app_name');
  }

  void _navigateByIndex(int index) {
    final items = _flatItems(context);
    if (index >= items.length) return;

    context.read<ShellState>().selectIndex(index);
    context.go(items[index].route);

    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    // Narrow rebuild triggers: only when nav items or role change.
    context.select<BlueprintNavigationController, bool>((c) => c.useFallbackNavigation);
    context.select<BlueprintNavigationController, int>((c) => c.navItems.length);
    context.select<AppState, String>((s) => s.currentRole.id);
    context.select<AppState, bool>((s) => s.isSuperAdmin);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,

      drawer: isMobile
          ? Drawer(
              backgroundColor: AppColors.surface,
              child: SafeArea(
                child: AppSidebar(onItemTap: _navigateByIndex, forceExpanded: true),
              ),
            )
          : null,

      bottomNavigationBar: isMobile ? _buildBottomNav(context) : null,

      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile)
              AppSidebar(onItemTap: _navigateByIndex),

            Expanded(
              child: Column(
                children: [
                  AppTopBar(
                    title: _currentTitle(context),
                    onMenuTap: isMobile ? () => _scaffoldKey.currentState?.openDrawer() : null,
                  ),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final shell = context.watch<ShellState>();
    final items = _flatItems(context);

    // Bottom nav: first 4 items
    final bottomItems = items.take(4).toList();
    int bottomIndex = -1;
    for (int i = 0; i < bottomItems.length; i++) {
      final flatIdx = items.indexOf(bottomItems[i]);
      if (flatIdx == shell.selectedIndex) {
        bottomIndex = i;
        break;
      }
    }

    return NavigationBar(
      selectedIndex: bottomIndex >= 0 ? bottomIndex : 0,
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primarySurface,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) {
        final flatIdx = items.indexOf(bottomItems[i]);
        _navigateByIndex(flatIdx);
      },
      destinations: bottomItems.map((item) => NavigationDestination(
        icon: Icon(item.icon, color: AppColors.neutral500),
        selectedIcon: Icon(item.icon, color: AppColors.primary),
        label: tr(context, item.labelKey),
      )).toList(),
    );
  }
}
