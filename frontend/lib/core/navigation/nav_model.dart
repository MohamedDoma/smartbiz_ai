// SmartBiz AI — Navigation model with localization keys.
import 'package:flutter/material.dart';

class NavItem {
  final String id;
  final String labelKey; // Localization key
  final IconData icon;
  final String route;
  final bool superAdminOnly;

  const NavItem({
    required this.id,
    required this.labelKey,
    required this.icon,
    required this.route,
    this.superAdminOnly = false,
  });
}

class NavSection {
  final String titleKey; // Localization key
  final List<NavItem> items;

  const NavSection({required this.titleKey, required this.items});
}

/// All navigation sections for the ERP shell.
const List<NavSection> appNavigation = [
  NavSection(titleKey: 'nav_section_core', items: [
    NavItem(id: 'dashboard',  labelKey: 'nav_dashboard',  icon: Icons.dashboard_outlined,           route: '/dashboard'),
    NavItem(id: 'ai_chat',    labelKey: 'nav_ai_chat',    icon: Icons.auto_awesome_outlined,        route: '/ai-chat'),
    NavItem(id: 'advisor',    labelKey: 'nav_advisor',    icon: Icons.lightbulb_outlined,           route: '/advisor'),
  ]),
  NavSection(titleKey: 'nav_section_business', items: [
    NavItem(id: 'invoices',   labelKey: 'nav_sales',      icon: Icons.point_of_sale_outlined,       route: '/invoices'),
    NavItem(id: 'payments',   labelKey: 'nav_payments',   icon: Icons.payments_outlined,            route: '/payments'),
    NavItem(id: 'pos',        labelKey: 'nav_pos',        icon: Icons.point_of_sale_outlined,       route: '/pos'),
    NavItem(id: 'products',   labelKey: 'nav_products',   icon: Icons.inventory_2_outlined,         route: '/products'),
    NavItem(id: 'inventory',  labelKey: 'nav_inventory',  icon: Icons.warehouse_outlined,           route: '/inventory'),
    NavItem(id: 'customers',  labelKey: 'nav_customers',  icon: Icons.people_outline,               route: '/customers'),
    NavItem(id: 'pipelines',  labelKey: 'nav_pipelines',  icon: Icons.linear_scale_outlined,        route: '/pipelines'),
  ]),
  NavSection(titleKey: 'nav_section_finance', items: [
    NavItem(id: 'accounting', labelKey: 'nav_accounting', icon: Icons.account_balance_outlined,     route: '/accounting'),
    NavItem(id: 'reports',    labelKey: 'nav_reports',    icon: Icons.bar_chart_outlined,           route: '/reports'),
  ]),
  NavSection(titleKey: 'nav_section_organization', items: [
    NavItem(id: 'employees',  labelKey: 'nav_employees',  icon: Icons.badge_outlined,               route: '/employees'),
    NavItem(id: 'settings',   labelKey: 'nav_settings',   icon: Icons.settings_outlined,            route: '/settings'),
  ]),
];

/// Super admin navigation (only visible to super admin role).
const NavSection superAdminNav = NavSection(titleKey: 'nav_section_admin', items: [
  NavItem(id: 'admin', labelKey: 'nav_admin', icon: Icons.admin_panel_settings_outlined, route: '/admin', superAdminOnly: true),
]);
