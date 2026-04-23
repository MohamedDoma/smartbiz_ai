/// Navigation model — role-aware ERP navigation items.
import 'package:flutter/material.dart';

class NavItem {
  final String id;
  final String label;
  final IconData icon;
  final String route;
  final List<String> requiredRoles; // empty = all roles
  final bool superAdminOnly;

  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.route,
    this.requiredRoles = const [],
    this.superAdminOnly = false,
  });
}

class NavSection {
  final String title;
  final List<NavItem> items;

  const NavSection({required this.title, required this.items});
}

/// All navigation sections for the ERP shell.
const List<NavSection> appNavigation = [
  NavSection(title: 'Core', items: [
    NavItem(id: 'dashboard',  label: 'Dashboard',  icon: Icons.dashboard_outlined,           route: '/dashboard'),
    NavItem(id: 'ai_chat',    label: 'AI Chat',    icon: Icons.auto_awesome_outlined,        route: '/ai-chat'),
    NavItem(id: 'advisor',    label: 'Advisor',    icon: Icons.lightbulb_outlined,           route: '/advisor'),
  ]),
  NavSection(title: 'Business', items: [
    NavItem(id: 'sales',      label: 'Sales',      icon: Icons.point_of_sale_outlined,       route: '/sales'),
    NavItem(id: 'products',   label: 'Products',   icon: Icons.inventory_2_outlined,         route: '/products'),
    NavItem(id: 'inventory',  label: 'Inventory',  icon: Icons.warehouse_outlined,           route: '/inventory'),
    NavItem(id: 'customers',  label: 'Customers',  icon: Icons.people_outline,               route: '/customers'),
  ]),
  NavSection(title: 'Finance', items: [
    NavItem(id: 'accounting', label: 'Accounting', icon: Icons.account_balance_outlined,     route: '/accounting'),
    NavItem(id: 'reports',    label: 'Reports',    icon: Icons.bar_chart_outlined,           route: '/reports'),
  ]),
  NavSection(title: 'Organization', items: [
    NavItem(id: 'employees',  label: 'Employees',  icon: Icons.badge_outlined,               route: '/employees'),
    NavItem(id: 'settings',   label: 'Settings',   icon: Icons.settings_outlined,            route: '/settings'),
  ]),
];

/// Super admin navigation (only visible to super admin).
const NavSection superAdminNav = NavSection(title: 'Admin', items: [
  NavItem(id: 'admin', label: 'Super Admin', icon: Icons.admin_panel_settings_outlined, route: '/admin', superAdminOnly: true),
]);
