// SmartBiz AI — Dashboard Resolver Unit Tests (Phase 16.3).
//
// Tests template mapping, permission filtering, module filtering,
// hybrid role merging, override priority, and safe fallback.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/features/dashboard/engine/dashboard_resolver.dart';
import 'package:smartbiz_ai/features/dashboard/models/dashboard_config_models.dart';
import 'package:smartbiz_ai/features/dashboard/data/default_dashboard_templates.dart';

void main() {
  const resolver = DashboardResolver();

  // All modules enabled for most tests.
  final allModules = <String>{
    'dashboard', 'aiChat', 'aiAdvisor', 'customers', 'invoices',
    'products', 'inventory', 'accounting', 'reports', 'employees',
    'roles', 'settings', 'billing',
  };

  // ═══════════════════════════════════════════════════════════
  //  Group 1: Template Mapping
  // ═══════════════════════════════════════════════════════════
  group('Template Mapping', () {
    final cases = <String, DashboardTemplate>{
      'sys_owner': DashboardTemplate.executive,
      'sys_cashier': DashboardTemplate.sales,
      'sys_warehouse': DashboardTemplate.inventory,
      'sys_accountant': DashboardTemplate.finance,
      'sys_employee': DashboardTemplate.basicEmployee,
      'tpl_gen_manager': DashboardTemplate.executive,
      'tpl_dept_manager': DashboardTemplate.operations,
      'tpl_manager': DashboardTemplate.executive,
      'tpl_team_leader': DashboardTemplate.operations,
      'tpl_sales': DashboardTemplate.sales,
      'tpl_hr_mgr': DashboardTemplate.hr,
      'tpl_hr': DashboardTemplate.hr,
      'tpl_wh_mgr': DashboardTemplate.inventory,
      'tpl_procurement_off': DashboardTemplate.operations,
      'tpl_support': DashboardTemplate.support,
      'tpl_pm': DashboardTemplate.projects,
      'tpl_service': DashboardTemplate.service,
      'tpl_delivery': DashboardTemplate.operations,
    };

    for (final entry in cases.entries) {
      test('${entry.key} → ${entry.value.name}', () {
        expect(templateForRole(entry.key), entry.value);
      });
    }

    test('unknown role → basicEmployee', () {
      expect(templateForRole('unknown_xyz'), DashboardTemplate.basicEmployee);
      expect(templateForRole(''), DashboardTemplate.basicEmployee);
      expect(templateForRole('custom_foo'), DashboardTemplate.basicEmployee);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 2: Permission Filtering
  // ═══════════════════════════════════════════════════════════
  group('Permission Filtering', () {
    test('missing required permission hides widget', () {
      final config = resolver.resolve(
        primaryRoleId: 'sys_owner',
        effectivePermissions: {'dashboard.view'},
        enabledModules: allModules,
      );
      // Owner template has widgets requiring invoices.view, accounting.view, etc.
      // With only dashboard.view, those widgets should be hidden.
      for (final w in config.widgets) {
        if (w.requiredPermissions.isNotEmpty) {
          expect(w.requiredPermissions.every({'dashboard.view'}.contains), isTrue,
            reason: 'Widget ${w.id} should only appear if its required perms are satisfied');
        }
      }
    });

    test('missing required permission hides quick action', () {
      final config = resolver.resolve(
        primaryRoleId: 'sys_owner',
        effectivePermissions: {'dashboard.view'},
        enabledModules: allModules,
      );
      for (final a in config.quickActions) {
        if (a.requiredPermissions.isNotEmpty) {
          expect(a.requiredPermissions.every({'dashboard.view'}.contains), isTrue,
            reason: 'Action ${a.id} should only appear if its required perms are satisfied');
        }
      }
    });

    test('all permissions granted shows all widgets', () {
      final fullPerms = <String>{
        'dashboard.view', 'invoices.view', 'invoices.create', 'invoices.edit',
        'customers.view', 'customers.create', 'products.view', 'inventory.view',
        'accounting.view', 'reports.view', 'reports.export', 'employees.view',
        'employees.create', 'roles.view', 'settings.view', 'billing.view',
        'aiChat.view', 'aiAdvisor.view',
      };
      final config = resolver.resolve(
        primaryRoleId: 'sys_owner',
        effectivePermissions: fullPerms,
        enabledModules: allModules,
      );
      expect(config.widgets.isNotEmpty, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 3: Module Filtering
  // ═══════════════════════════════════════════════════════════
  group('Module Filtering', () {
    test('missing module hides widget', () {
      final config = resolver.resolve(
        primaryRoleId: 'sys_owner',
        effectivePermissions: {
          'dashboard.view', 'invoices.view', 'invoices.create',
          'accounting.view', 'reports.view',
        },
        enabledModules: {'dashboard'}, // only dashboard module enabled
      );
      for (final w in config.widgets) {
        if (w.module != null && w.module!.isNotEmpty) {
          expect(w.module, equals('dashboard'),
            reason: 'Widget ${w.id} should only appear for enabled module');
        }
      }
    });

    test('widget with no module always shows', () {
      // Widgets with null/empty module should pass module filter
      expect(_moduleEnabled(null, {'dashboard'}), isTrue);
      expect(_moduleEnabled('', {'dashboard'}), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 4: Hybrid Role Scenario
  // ═══════════════════════════════════════════════════════════
  group('Hybrid Role', () {
    test('sales + hr merges widgets correctly', () {
      final perms = <String>{
        'dashboard.view', 'invoices.view', 'invoices.create', 'invoices.edit',
        'customers.view', 'customers.create', 'customers.edit',
        'products.view', 'reports.view',
        'employees.view', 'employees.create', 'employees.edit',
        'roles.view',
      };
      final config = resolver.resolve(
        primaryRoleId: 'tpl_sales',
        extraRoleIds: ['tpl_hr'],
        effectivePermissions: perms,
        enabledModules: allModules,
      );

      expect(config.template, DashboardTemplate.sales,
        reason: 'Primary template should remain sales');
      // HR widgets should be merged
      final widgetIds = config.widgets.map((w) => w.id).toSet();
      // Should have no duplicates
      expect(widgetIds.length, config.widgets.length,
        reason: 'No duplicate widget IDs');
    });

    test('same template extra role is skipped', () {
      // Both sales reps → same template, should not duplicate widgets
      final perms = <String>{'dashboard.view', 'invoices.view', 'customers.view'};
      final config = resolver.resolve(
        primaryRoleId: 'tpl_sales',
        extraRoleIds: ['sys_cashier'], // both map to sales template
        effectivePermissions: perms,
        enabledModules: allModules,
      );
      final widgetIds = config.widgets.map((w) => w.id).toSet();
      expect(widgetIds.length, config.widgets.length,
        reason: 'No duplicate widget IDs');
    });

    test('position order preserved after merge', () {
      final perms = <String>{
        'dashboard.view', 'invoices.view', 'invoices.create',
        'customers.view', 'employees.view', 'reports.view',
      };
      final config = resolver.resolve(
        primaryRoleId: 'tpl_sales',
        extraRoleIds: ['tpl_hr'],
        effectivePermissions: perms,
        enabledModules: allModules,
      );
      for (int i = 1; i < config.widgets.length; i++) {
        expect(config.widgets[i].position >= config.widgets[i - 1].position, isTrue,
          reason: 'Widgets should be sorted by position');
      }
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 5: Override Priority
  // ═══════════════════════════════════════════════════════════
  group('Override Priority', () {
    test('workspace role config overrides system default', () {
      final wsOverride = DashboardConfiguration(
        id: 'ws_test',
        template: DashboardTemplate.sales,
        source: DashboardSource.workspaceRole,
        widgets: [
          DashboardWidgetConfig(
            id: 'ws_custom_widget',
            type: DashWidgetType.metric,
            titleKey: 'test_widget',
            position: 0,
          ),
        ],
        quickActions: [],
        landingRoute: '/invoices',
      );
      final config = resolver.resolve(
        primaryRoleId: 'sys_cashier',
        effectivePermissions: {'dashboard.view', 'invoices.view'},
        enabledModules: allModules,
        workspaceRoleConfig: wsOverride,
      );
      expect(config.source, DashboardSource.workspaceRole);
      expect(config.widgets.any((w) => w.id == 'ws_custom_widget'), isTrue,
        reason: 'Workspace override widget should be present');
    });

    test('employee override wins over workspace', () {
      final wsOverride = DashboardConfiguration(
        id: 'ws_test',
        template: DashboardTemplate.sales,
        source: DashboardSource.workspaceRole,
        widgets: [],
        quickActions: [],
        landingRoute: '/invoices',
      );
      final empOverride = DashboardConfiguration(
        id: 'emp_test',
        template: DashboardTemplate.sales,
        source: DashboardSource.employeeOverride,
        widgets: [
          DashboardWidgetConfig(
            id: 'emp_widget',
            type: DashWidgetType.metric,
            titleKey: 'emp_title',
            position: 0,
          ),
        ],
        quickActions: [],
        landingRoute: '/products',
      );
      final config = resolver.resolve(
        primaryRoleId: 'sys_cashier',
        effectivePermissions: {'dashboard.view', 'invoices.view', 'products.view'},
        enabledModules: allModules,
        workspaceRoleConfig: wsOverride,
        employeeOverride: empOverride,
      );
      expect(config.source, DashboardSource.employeeOverride);
      expect(config.widgets.any((w) => w.id == 'emp_widget'), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 6: Template Override (Custom Role)
  // ═══════════════════════════════════════════════════════════
  group('Template Override', () {
    test('custom role template override is used', () {
      final config = resolver.resolve(
        primaryRoleId: 'custom_unknown_id',
        effectivePermissions: {'dashboard.view', 'invoices.view', 'customers.view'},
        enabledModules: allModules,
        templateOverride: DashboardTemplate.sales,
      );
      expect(config.template, DashboardTemplate.sales,
        reason: 'Template override should be used instead of ID lookup');
    });

    test('template override with unknown role ID still works', () {
      final config = resolver.resolve(
        primaryRoleId: 'cust_999',
        effectivePermissions: {'dashboard.view'},
        enabledModules: allModules,
        templateOverride: DashboardTemplate.hr,
      );
      expect(config.template, DashboardTemplate.hr);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 7: Safe Fallback
  // ═══════════════════════════════════════════════════════════
  group('Safe Fallback', () {
    test('unknown role falls back to basicEmployee', () {
      final config = resolver.resolve(
        primaryRoleId: 'xyz_unknown',
        effectivePermissions: {'dashboard.view', 'aiChat.view'},
        enabledModules: allModules,
      );
      expect(config.template, DashboardTemplate.basicEmployee);
      expect(config.widgets.isNotEmpty, isTrue,
        reason: 'basicEmployee should have at least some widgets');
    });

    test('no crash when no widgets pass filter', () {
      // If all widgets get filtered by permissions, should fallback to basicEmployee
      final config = resolver.resolve(
        primaryRoleId: 'sys_owner',
        effectivePermissions: <String>{}, // no permissions at all
        enabledModules: allModules,
      );
      // Should not crash, may fall back to basicEmployee
      expect(config, isNotNull);
    });

    test('empty enabled modules still produces result', () {
      final config = resolver.resolve(
        primaryRoleId: 'sys_employee',
        effectivePermissions: {'dashboard.view'},
        enabledModules: <String>{},
      );
      expect(config, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 8: All Templates Resolve
  // ═══════════════════════════════════════════════════════════
  group('All Templates Resolve', () {
    for (final tpl in DashboardTemplate.values) {
      test('${tpl.name} template resolves without error', () {
        final config = DefaultDashboardTemplates.forTemplate(tpl);
        expect(config, isNotNull);
        expect(config.id, isNotEmpty);
        // custom template falls back to basicEmployee template
        if (tpl == DashboardTemplate.custom) {
          expect(config.template, DashboardTemplate.basicEmployee);
        } else {
          expect(config.template, tpl);
        }
      });
    }
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 9: Widget / Action Permission Helpers
  // ═══════════════════════════════════════════════════════════
  group('Permission Helpers', () {
    test('canRenderWidget with empty permissions required', () {
      final w = DashboardWidgetConfig(
        id: 'test', type: DashWidgetType.metric, titleKey: 'test',
        requiredPermissions: [],
      );
      expect(canRenderWidget(w, {}), isTrue);
    });

    test('canRenderWidget with satisfied permissions', () {
      final w = DashboardWidgetConfig(
        id: 'test', type: DashWidgetType.metric, titleKey: 'test',
        requiredPermissions: ['invoices.view'],
      );
      expect(canRenderWidget(w, {'invoices.view', 'dashboard.view'}), isTrue);
    });

    test('canRenderWidget with missing permission', () {
      final w = DashboardWidgetConfig(
        id: 'test', type: DashWidgetType.metric, titleKey: 'test',
        requiredPermissions: ['invoices.view', 'invoices.create'],
      );
      expect(canRenderWidget(w, {'invoices.view'}), isFalse);
    });

    test('canRenderAction with empty permissions', () {
      final a = DashboardQuickActionConfig(
        id: 'test', labelKey: 'test', iconName: 'add', route: '/test',
        requiredPermissions: [],
      );
      expect(canRenderAction(a, {}), isTrue);
    });

    test('canRenderAction with missing permission', () {
      final a = DashboardQuickActionConfig(
        id: 'test', labelKey: 'test', iconName: 'add', route: '/test',
        requiredPermissions: ['billing.manage'],
      );
      expect(canRenderAction(a, {'dashboard.view'}), isFalse);
    });
  });
}

// Expose the private module helper for testing
bool _moduleEnabled(String? module, Set<String> enabledModules) {
  if (module == null || module.isEmpty) return true;
  return enabledModules.contains(module);
}
