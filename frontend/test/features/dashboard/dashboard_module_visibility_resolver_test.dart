// SmartBiz AI — Dashboard Module Visibility Resolver Tests (Phase 17).
//
// Unit tests for DashboardModuleVisibilityResolver covering widget/action
// ownership resolution, batch filtering, and cache consistency.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/core/modules/erp_module_models.dart';
import 'package:smartbiz_ai/features/dashboard/dashboard_module_visibility_resolver.dart';

void main() {
  setUp(() {
    DashboardModuleVisibilityResolver.clearCache();
  });

  tearDown(() {
    DashboardModuleVisibilityResolver.clearCache();
  });

  /// Baseline: all commonly used modules enabled.
  final allEnabled = <ErpModuleId>{
    ErpModuleId.dashboard,
    ErpModuleId.aiChat,
    ErpModuleId.aiAdvisor,
    ErpModuleId.customers,
    ErpModuleId.invoices,
    ErpModuleId.products,
    ErpModuleId.inventory,
    ErpModuleId.accounting,
    ErpModuleId.expenses,
    ErpModuleId.reports,
    ErpModuleId.employees,
    ErpModuleId.settings,
  };

  // ═══════════════════════════════════════════════════════════
  //  1. Unknown Ownership (Default Allow)
  // ═══════════════════════════════════════════════════════════
  group('Unknown Ownership', () {
    test('unknown widget ID is visible by default', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_nonexistent_widget',
          enabledModules: {},
        ),
        isTrue,
      );
    });

    test('unknown action ID is visible by default', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_nonexistent_action',
          enabledModules: {},
        ),
        isTrue,
      );
    });

    test('empty widget ID is visible by default', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: '',
          enabledModules: {},
        ),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  2. Dashboard / System Ownership
  // ═══════════════════════════════════════════════════════════
  group('Dashboard System Widgets', () {
    test('w_alerts visible when dashboard enabled', () {
      // w_alerts is only in dashboard's supportedWidgetIds.
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_alerts',
          enabledModules: {ErpModuleId.dashboard},
        ),
        isTrue,
      );
    });

    test('w_recent_activity visible when dashboard enabled', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_recent_activity',
          enabledModules: {ErpModuleId.dashboard},
        ),
        isTrue,
      );
    });

    test('w_alerts hidden when dashboard intentionally omitted', () {
      // Deterministic: dashboard owns w_alerts; omitting dashboard hides it.
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_alerts',
          enabledModules: {},
        ),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  3. Widget Ownership via Config Module (apiId)
  // ═══════════════════════════════════════════════════════════
  group('Widget Ownership via Config Module', () {
    test('visible when moduleApiId matches enabled module', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.customers},
          moduleApiId: 'customers',
        ),
        isTrue,
      );
    });

    test('hidden when moduleApiId matches disabled module', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.dashboard},
          moduleApiId: 'customers',
        ),
        isFalse,
      );
    });

    test('moduleApiId takes priority over registry lookup', () {
      // w_customer_summary is owned by customers in registry.
      // Pass moduleApiId='invoices' — should check invoices, not customers.
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.invoices}, // customers NOT enabled
          moduleApiId: 'invoices',
        ),
        isTrue,
      );
    });

    test('invalid moduleApiId falls back to registry lookup', () {
      // Unknown apiId → falls through → registry says customers owns it.
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.customers},
          moduleApiId: 'nonexistent_module',
        ),
        isTrue, // registry lookup finds customers → enabled → visible
      );
    });

    test('empty moduleApiId falls back to registry lookup', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.customers},
          moduleApiId: '',
        ),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  4. Widget Ownership via Registry
  // ═══════════════════════════════════════════════════════════
  group('Widget Ownership via Registry', () {
    test('w_customer_summary owned by customers module', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.customers},
        ),
        isTrue,
      );
    });

    test('w_customer_summary hidden when customers disabled', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_customer_summary',
          enabledModules: {ErpModuleId.dashboard},
        ),
        isFalse,
      );
    });

    test('w_product_count owned by products module', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_product_count',
          enabledModules: {ErpModuleId.products},
        ),
        isTrue,
      );
    });

    test('w_product_count hidden when products disabled', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_product_count',
          enabledModules: {},
        ),
        isFalse,
      );
    });

    test('w_inventory_summary owned by inventory module', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_inventory_summary',
          enabledModules: {ErpModuleId.inventory},
        ),
        isTrue,
      );
    });

    test('w_employee_summary owned by employees module', () {
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_employee_summary',
          enabledModules: {ErpModuleId.employees},
        ),
        isTrue,
      );
    });

    // Shared widget ID: w_revenue appears in both dashboard (order 10) and
    // invoices (order 110). Last-write-wins → invoices owns it.
    test('w_revenue owned by invoices (last-write-wins from registry order)', () {
      // Invoices enabled, dashboard not → still visible.
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_revenue',
          enabledModules: {ErpModuleId.invoices},
        ),
        isTrue,
      );
      // Invoices disabled → hidden, even if dashboard enabled.
      expect(
        DashboardModuleVisibilityResolver.isWidgetVisible(
          widgetId: 'w_revenue',
          enabledModules: {ErpModuleId.dashboard},
        ),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  5. Quick Action Ownership via Registry
  // ═══════════════════════════════════════════════════════════
  group('Quick Action Ownership via Registry', () {
    test('qa_new_customer owned by customers module', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_new_customer',
          enabledModules: {ErpModuleId.customers},
        ),
        isTrue,
      );
    });

    test('qa_new_customer hidden when customers disabled', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_new_customer',
          enabledModules: {ErpModuleId.dashboard},
        ),
        isFalse,
      );
    });

    test('qa_new_invoice owned by invoices module', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_new_invoice',
          enabledModules: {ErpModuleId.invoices},
        ),
        isTrue,
      );
    });

    test('qa_new_invoice hidden when invoices disabled', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_new_invoice',
          enabledModules: {},
        ),
        isFalse,
      );
    });

    test('qa_adjust_stock owned by inventory module', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_adjust_stock',
          enabledModules: {ErpModuleId.inventory},
        ),
        isTrue,
      );
    });

    test('qa_invite_employee owned by employees module', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_invite_employee',
          enabledModules: {ErpModuleId.employees},
        ),
        isTrue,
      );
    });

    // Shared action: qa_ai_chat in dashboard (10) and aiChat (20).
    // Last-write-wins → aiChat owns it.
    test('qa_ai_chat owned by aiChat (last-write-wins)', () {
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_ai_chat',
          enabledModules: {ErpModuleId.aiChat},
        ),
        isTrue,
      );
      expect(
        DashboardModuleVisibilityResolver.isActionVisible(
          actionId: 'qa_ai_chat',
          enabledModules: {ErpModuleId.dashboard}, // aiChat not enabled
        ),
        isFalse,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  6. Batch Filters
  // ═══════════════════════════════════════════════════════════
  group('Batch Filters', () {
    test('visibleWidgetIds returns only visible widgets', () {
      final result = DashboardModuleVisibilityResolver.visibleWidgetIds(
        widgetIds: ['w_customer_summary', 'w_product_count', 'w_alerts', 'w_unknown'],
        enabledModules: {ErpModuleId.dashboard, ErpModuleId.customers},
      );
      // customers enabled → w_customer_summary visible
      // products not enabled → w_product_count hidden
      // dashboard enabled → w_alerts visible
      // unknown → visible by default
      expect(result, ['w_customer_summary', 'w_alerts', 'w_unknown']);
    });

    test('visibleActionIds returns only visible actions', () {
      final result = DashboardModuleVisibilityResolver.visibleActionIds(
        actionIds: ['qa_new_customer', 'qa_new_invoice', 'qa_unknown'],
        enabledModules: {ErpModuleId.customers},
      );
      // customers enabled → qa_new_customer visible
      // invoices not enabled → qa_new_invoice hidden
      // unknown → visible by default
      expect(result, ['qa_new_customer', 'qa_unknown']);
    });

    test('batch preserves input order', () {
      final result = DashboardModuleVisibilityResolver.visibleWidgetIds(
        widgetIds: ['w_alerts', 'w_customer_summary', 'w_inventory_summary'],
        enabledModules: allEnabled,
      );
      expect(result, ['w_alerts', 'w_customer_summary', 'w_inventory_summary']);
    });

    test('batch with empty input returns empty', () {
      final result = DashboardModuleVisibilityResolver.visibleWidgetIds(
        widgetIds: [],
        enabledModules: allEnabled,
      );
      expect(result, isEmpty);
    });

    test('batch with all disabled returns only unknown/system items', () {
      final result = DashboardModuleVisibilityResolver.visibleWidgetIds(
        widgetIds: ['w_customer_summary', 'w_product_count', 'w_unknown'],
        enabledModules: {},
      );
      expect(result, ['w_unknown']);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  7. Cache Behavior
  // ═══════════════════════════════════════════════════════════
  group('Cache Behavior', () {
    test('repeated calls return consistent results', () {
      final r1 = DashboardModuleVisibilityResolver.isWidgetVisible(
        widgetId: 'w_customer_summary',
        enabledModules: {ErpModuleId.customers},
      );
      final r2 = DashboardModuleVisibilityResolver.isWidgetVisible(
        widgetId: 'w_customer_summary',
        enabledModules: {ErpModuleId.customers},
      );
      expect(r1, r2);
    });

    test('clearCache does not change behavior', () {
      final before = DashboardModuleVisibilityResolver.isWidgetVisible(
        widgetId: 'w_product_count',
        enabledModules: {ErpModuleId.products},
      );
      DashboardModuleVisibilityResolver.clearCache();
      final after = DashboardModuleVisibilityResolver.isWidgetVisible(
        widgetId: 'w_product_count',
        enabledModules: {ErpModuleId.products},
      );
      expect(before, after);
    });

    test('action cache returns consistent results', () {
      final r1 = DashboardModuleVisibilityResolver.isActionVisible(
        actionId: 'qa_new_invoice',
        enabledModules: {ErpModuleId.invoices},
      );
      DashboardModuleVisibilityResolver.clearCache();
      final r2 = DashboardModuleVisibilityResolver.isActionVisible(
        actionId: 'qa_new_invoice',
        enabledModules: {ErpModuleId.invoices},
      );
      expect(r1, r2);
    });
  });
}
