// SmartBiz AI — Main responsive app shell.
///
/// Desktop: sidebar + top bar + content
/// Tablet:  collapsed sidebar + top bar + content
/// Mobile:  drawer + bottom nav + top bar + content
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/navigation/nav_model.dart';
import '../../core/navigation/shell_state.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_colors.dart';
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

  List<NavItem> get _flatItems {
    final items = <NavItem>[];
    for (final section in appNavigation) {
      items.addAll(section.items);
    }
    final shell = context.read<ShellState>();
    if (shell.isSuperAdmin) {
      items.addAll(superAdminNav.items);
    }
    return items;
  }

  String get _currentTitle {
    final shell = context.watch<ShellState>();
    final items = _flatItems;
    if (shell.selectedIndex < items.length) {
      return items[shell.selectedIndex].label;
    }
    return 'SmartBiz AI';
  }

  void _onNavTap(int index) {
    context.read<ShellState>().selectIndex(index);
    // Close drawer on mobile
    if (Responsive.isMobile(context) && _scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,

      // Mobile drawer
      drawer: isMobile ? Drawer(
        child: AppSidebar(onItemTap: _onNavTap),
      ) : null,

      // Mobile bottom nav
      bottomNavigationBar: isMobile ? _buildBottomNav(context) : null,

      body: Row(
        children: [
          // Sidebar for non-mobile
          if (!isMobile)
            AppSidebar(onItemTap: _onNavTap),

          // Content
          Expanded(
            child: Column(
              children: [
                AppTopBar(
                  title: _currentTitle,
                  onMenuTap: isMobile ? () => _scaffoldKey.currentState?.openDrawer() : null,
                ),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final shell = context.watch<ShellState>();
    // Show only first 5 items in bottom nav
    final items = _flatItems.take(5).toList();

    return NavigationBar(
      selectedIndex: shell.selectedIndex < 5 ? shell.selectedIndex : 0,
      onDestinationSelected: _onNavTap,
      destinations: items.map((item) => NavigationDestination(
        icon: Icon(item.icon),
        label: item.label,
      )).toList(),
    );
  }
}
