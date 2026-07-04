// SmartBiz AI — Module Navigation Adapter (Phase 17).
//
// Converts ResolvedNavItem (from ModuleNavigationResolver) into the
// existing NavItem model used by the sidebar shell.
// No Provider, no BuildContext, no navigation calls.
import 'package:flutter/material.dart';
import '../navigation/nav_model.dart';
import 'module_navigation_resolver.dart';

class ModuleNavigationAdapter {
  const ModuleNavigationAdapter();

  /// Convert a single resolved item to the legacy NavItem.
  NavItem toNavItem(ResolvedNavItem item) {
    return NavItem(
      id: item.navItemId,
      labelKey: item.labelKey,
      icon: _resolveIcon(item.iconId),
      route: item.route,
    );
  }

  /// Convert a full resolved list to legacy NavItems.
  /// Returns an immutable list. Order is preserved from the input.
  List<NavItem> toNavItems(List<ResolvedNavItem> items) {
    return List.unmodifiable(items.map(toNavItem));
  }

  // ─────────────────────────────────────────────────────────
  //  Icon string → IconData mapping
  // ─────────────────────────────────────────────────────────

  /// Maps a registry icon identifier string to a Material IconData.
  /// Falls back to [Icons.extension_outlined] for unknown IDs.
  static IconData _resolveIcon(String iconId) =>
      _iconMap[iconId] ?? Icons.extension_outlined;

  /// Exhaustive mapping of all icon IDs used in ErpModuleRegistry.
  /// Uses outlined variants where the sidebar convention prefers them.
  static const Map<String, IconData> _iconMap = {
    // Core
    'dashboard_outlined':      Icons.dashboard_outlined,
    'auto_awesome':            Icons.auto_awesome_outlined,
    'lightbulb':               Icons.lightbulb_outlined,
    'notifications':           Icons.notifications_outlined,
    'settings':                Icons.settings_outlined,

    // CRM
    'people':                  Icons.people_outline,
    'leaderboard':             Icons.leaderboard_outlined,
    'trending_up':             Icons.trending_up_outlined,

    // Sales
    'request_quote':           Icons.request_quote_outlined,
    'receipt_long':            Icons.receipt_long_outlined,
    'payments':                Icons.payments_outlined,
    'point_of_sale':           Icons.point_of_sale_outlined,
    'autorenew':               Icons.autorenew_outlined,

    // Inventory
    'inventory_2':             Icons.inventory_2_outlined,
    'warehouse':               Icons.warehouse_outlined,
    'domain':                  Icons.domain_outlined,
    'swap_horiz':              Icons.swap_horiz_outlined,
    'local_shipping':          Icons.local_shipping_outlined,
    'shopping_cart':           Icons.shopping_cart_outlined,
    'assignment':              Icons.assignment_outlined,

    // Finance
    'account_balance':         Icons.account_balance_outlined,
    'money_off':               Icons.money_off_outlined,
    'bar_chart':               Icons.bar_chart_outlined,
    'account_balance_wallet':  Icons.account_balance_wallet_outlined,
    'savings':                 Icons.savings_outlined,

    // People
    'badge':                   Icons.badge_outlined,
    'shield':                  Icons.shield_outlined,
    'business':                Icons.business_outlined,
    'groups':                  Icons.groups_outlined,
    'access_time':             Icons.access_time_outlined,
    'event_busy':              Icons.event_busy_outlined,

    // Projects & Service
    'folder':                  Icons.folder_outlined,
    'checklist':               Icons.checklist_outlined,
    'timer':                   Icons.timer_outlined,
    'calendar_today':          Icons.calendar_today_outlined,
    'schedule':                Icons.schedule_outlined,
    'build':                   Icons.build_outlined,
    'support_agent':           Icons.support_agent_outlined,

    // Restaurant
    'table_restaurant':        Icons.table_restaurant_outlined,
    'restaurant_menu':         Icons.restaurant_menu_outlined,
    'kitchen':                 Icons.kitchen_outlined,
    'menu_book':               Icons.menu_book_outlined,
    'egg':                     Icons.egg_outlined,

    // Manufacturing
    'precision_manufacturing': Icons.precision_manufacturing_outlined,
    'account_tree':            Icons.account_tree_outlined,
    'factory':                 Icons.factory_outlined,

    // Logistics & Platform
    'directions_car':          Icons.directions_car_outlined,
    'store':                   Icons.store_outlined,
  };
}
