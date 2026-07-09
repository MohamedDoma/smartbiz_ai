// SmartBiz AI — Super Admin Shell layout.
// Standalone shell with its own sidebar, not dependent on customer workspace modules.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/responsive.dart';
import '../../../core/state/app_state.dart';

/// Navigation items for the Super Admin sidebar.
class _SaNavItem {
  final String id;
  final String labelKey;
  final IconData icon;
  final String route;
  const _SaNavItem(this.id, this.labelKey, this.icon, this.route);
}

const _saNavItems = <_SaNavItem>[
  _SaNavItem('plt_dashboard',  'sa_nav_dashboard',    Icons.dashboard_outlined,        '/platform'),
  _SaNavItem('plt_workspaces', 'plt_workspaces',      Icons.business_outlined,         '/platform/workspaces'),
  _SaNavItem('plt_users',      'plt_users',           Icons.people_outlined,           '/platform/users'),
  _SaNavItem('plt_campaigns',  'plt_campaigns',       Icons.campaign_outlined,         '/platform/campaigns'),
  _SaNavItem('plt_codes',      'plt_codes',           Icons.qr_code_2_outlined,        '/platform/codes'),
  _SaNavItem('plt_cards',      'plt_print_cards',     Icons.credit_card_outlined,      '/platform/cards'),
  _SaNavItem('plt_plans',      'sa_nav_plans',        Icons.card_membership_outlined,  '/platform/plans'),
  _SaNavItem('plt_health',     'sa_nav_health',       Icons.monitor_heart_outlined,    '/platform/health'),
  _SaNavItem('plt_usage',      'sa_nav_usage',        Icons.auto_awesome_outlined,     '/platform/usage'),
];

class SuperAdminShell extends StatefulWidget {
  final Widget child;
  const SuperAdminShell({super.key, required this.child});

  @override
  State<SuperAdminShell> createState() => _SuperAdminShellState();
}

class _SuperAdminShellState extends State<SuperAdminShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _sidebarExpanded = true;

  int _activeIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (int i = _saNavItems.length - 1; i >= 0; i--) {
      if (loc == _saNavItems[i].route || loc.startsWith('${_saNavItems[i].route}/')) {
        return i;
      }
    }
    return 0;
  }

  void _navigate(int index) {
    if (index >= _saNavItems.length) return;
    context.go(_saNavItems[index].route);
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final selectedIndex = _activeIndex(context);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: isMobile ? Drawer(
        backgroundColor: const Color(0xFF111827),
        child: SafeArea(child: _Sidebar(
          expanded: true,
          selectedIndex: selectedIndex,
          onTap: _navigate,
        )),
      ) : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!isMobile)
              _Sidebar(
                expanded: _sidebarExpanded && Responsive.isDesktop(context),
                selectedIndex: selectedIndex,
                onTap: _navigate,
              ),
            Expanded(
              child: Column(
                children: [
                  _TopBar(
                    title: tr(context, _saNavItems[selectedIndex].labelKey),
                    onMenuTap: isMobile ? () => _scaffoldKey.currentState?.openDrawer() : null,
                    onToggleSidebar: !isMobile ? () => setState(() => _sidebarExpanded = !_sidebarExpanded) : null,
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
}

// ═══════════════════════════════════════════════════════════
//  Super Admin Sidebar
// ═══════════════════════════════════════════════════════════

class _Sidebar extends StatelessWidget {
  final bool expanded;
  final int selectedIndex;
  final void Function(int) onTap;

  const _Sidebar({
    required this.expanded,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = expanded ? 240.0 : 68.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        border: Border(right: BorderSide(color: Color(0xFF1F2937))),
      ),
      child: Column(
        children: [
          // Logo area
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.admin_panel_settings, size: 18, color: AppColors.error),
                ),
                if (expanded) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(tr(context, 'sa_title'), style: AppTypography.labelLarge.copyWith(color: Colors.white)),
                ],
              ],
            ),
          ),
          const Divider(color: Color(0xFF1F2937), height: 1),
          const SizedBox(height: AppSpacing.sm),

          // Nav items
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              itemCount: _saNavItems.length,
              itemBuilder: (_, i) {
                final item = _saNavItems[i];
                final isSelected = i == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: isSelected ? AppColors.error.withValues(alpha: 0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => onTap(i),
                      borderRadius: BorderRadius.circular(10),
                      hoverColor: Colors.white.withValues(alpha: 0.05),
                      child: Container(
                        height: 42,
                        padding: EdgeInsets.symmetric(horizontal: expanded ? AppSpacing.md : 0),
                        child: Row(
                          mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                          children: [
                            Icon(item.icon, size: 20,
                              color: isSelected ? AppColors.error : const Color(0xFF9CA3AF)),
                            if (expanded) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(tr(context, item.labelKey),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected ? Colors.white : const Color(0xFF9CA3AF),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Back to workspace
          const Divider(color: Color(0xFF1F2937), height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => context.go('/dashboard'),
                borderRadius: BorderRadius.circular(10),
                hoverColor: Colors.white.withValues(alpha: 0.05),
                child: Container(
                  height: 42,
                  padding: EdgeInsets.symmetric(horizontal: expanded ? AppSpacing.md : 0),
                  child: Row(
                    mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.arrow_back, size: 18, color: Color(0xFF9CA3AF)),
                      if (expanded) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(tr(context, 'sa_back_workspace'),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Logout
          Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm, right: AppSpacing.sm, bottom: AppSpacing.sm),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => _handleLogout(context),
                borderRadius: BorderRadius.circular(10),
                hoverColor: AppColors.error.withValues(alpha: 0.08),
                child: Container(
                  height: 42,
                  padding: EdgeInsets.symmetric(horizontal: expanded ? AppSpacing.md : 0),
                  child: Row(
                    mainAxisAlignment: expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout, size: 18, color: AppColors.error.withValues(alpha: 0.7)),
                      if (expanded) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Text(tr(context, 'ux_logout'),
                          style: TextStyle(fontSize: 12, color: AppColors.error.withValues(alpha: 0.7))),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final app = context.read<AppState>();
    try {
      await app.signOutReal();
    } catch (_) {
      // signOutReal clears local state even on failure.
    }
    if (context.mounted) context.go('/login');
  }
}

// ═══════════════════════════════════════════════════════════
//  Super Admin Top Bar
// ═══════════════════════════════════════════════════════════

class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onMenuTap;
  final VoidCallback? onToggleSidebar;

  const _TopBar({required this.title, this.onMenuTap, this.onToggleSidebar});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          if (onMenuTap != null)
            IconButton(icon: const Icon(Icons.menu, size: 20), onPressed: onMenuTap),
          if (onToggleSidebar != null)
            IconButton(icon: const Icon(Icons.menu_open, size: 20), onPressed: onToggleSidebar),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.error, letterSpacing: 0.8)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: AppTypography.labelLarge),
          const Spacer(),
          // Language toggle
          IconButton(
            icon: Text(appState.uiLanguage == AppLanguage.en ? 'AR' : 'EN',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            onPressed: () => appState.setUiLanguage(
              appState.uiLanguage == AppLanguage.en ? AppLanguage.ar : AppLanguage.en,
            ),
            tooltip: tr(context, 'set_lang'),
          ),
        ],
      ),
    );
  }
}
