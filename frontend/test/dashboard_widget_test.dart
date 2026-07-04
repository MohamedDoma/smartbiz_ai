// SmartBiz AI — Dashboard Widget Tests (Phase 16.3).
//
// Tests DashboardPreview rendering, empty state, quick actions,
// Arabic localization, and hidden widget indicator.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/features/dashboard/models/dashboard_config_models.dart';
import 'package:smartbiz_ai/features/dashboard/widgets/dashboard_preview.dart';
import 'package:smartbiz_ai/core/l10n/app_localizations.dart';

/// Wraps a widget in a MaterialApp with SmartBiz localization.
Widget _app(Widget child, {AppLanguage lang = AppLanguage.en}) {
  return MaterialApp(
    home: AppLocaleProvider(
      language: lang,
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

DashboardConfiguration _testConfig({
  DashboardTemplate template = DashboardTemplate.executive,
  List<DashboardWidgetConfig>? widgets,
  List<DashboardQuickActionConfig>? actions,
  String landingRoute = '/dashboard',
}) {
  return DashboardConfiguration(
    id: 'test_config',
    template: template,
    source: DashboardSource.systemDefault,
    widgets: widgets ?? [
      DashboardWidgetConfig(
        id: 'w1',
        type: DashWidgetType.metric,
        titleKey: 'dw_revenue_today',
        position: 0,
      ),
      DashboardWidgetConfig(
        id: 'w2',
        type: DashWidgetType.aiInsight,
        titleKey: 'dw_ai_business_insight',
        position: 1,
      ),
    ],
    quickActions: actions ?? [
      DashboardQuickActionConfig(
        id: 'qa1',
        labelKey: 'dqa_new_invoice',
        iconName: 'add_circle',
        route: '/invoices/create',
        position: 0,
      ),
    ],
    landingRoute: landingRoute,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════
  //  Group 1: DashboardPreview Rendering
  // ═══════════════════════════════════════════════════════════
  group('DashboardPreview', () {
    testWidgets('renders template name and widgets', (tester) async {
      final config = _testConfig();
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config, totalWidgetCount: 5),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardPreview), findsOneWidget);
      // Template label should be localized (Executive)
      expect(find.text('Executive'), findsOneWidget);
      // Source badge should show (System Default)
      expect(find.text('System Default'), findsOneWidget);
    });

    testWidgets('renders empty widget list safely', (tester) async {
      final config = _testConfig(widgets: []);
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config, totalWidgetCount: 0),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardPreview), findsOneWidget);
      // Should show "No widgets available" message
      expect(find.text('No widgets available'), findsOneWidget);
    });

    testWidgets('shows hidden widget count when total > visible', (tester) async {
      final config = _testConfig(
        widgets: [
          DashboardWidgetConfig(
            id: 'only_one', type: DashWidgetType.metric,
            titleKey: 'dw_revenue_today', position: 0,
          ),
        ],
      );
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config, totalWidgetCount: 5),
      ));
      await tester.pumpAndSettle();

      // 5 total - 1 visible = 4 hidden
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.textContaining('4'), findsWidgets);
    });

    testWidgets('renders no actions message', (tester) async {
      final config = _testConfig(actions: []);
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No quick actions available'), findsOneWidget);
    });

    testWidgets('renders landing route', (tester) async {
      final config = _testConfig(landingRoute: '/products');
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('/products'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 2: Arabic Localization
  // ═══════════════════════════════════════════════════════════
  group('Arabic Localization', () {
    testWidgets('DashboardPreview renders in Arabic', (tester) async {
      final config = _testConfig();
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config),
        lang: AppLanguage.ar,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(DashboardPreview), findsOneWidget);
      // Arabic label for "Executive" template
      expect(find.text('تنفيذي'), findsOneWidget);
      // Arabic "System Default" source badge
      expect(find.text('افتراضي النظام'), findsOneWidget);
    });

    testWidgets('Arabic empty state renders correctly', (tester) async {
      final config = _testConfig(widgets: [], actions: []);
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config),
        lang: AppLanguage.ar,
      ));
      await tester.pumpAndSettle();

      // Arabic "No widgets available"
      expect(find.text('لا توجد عناصر متاحة'), findsOneWidget);
      // Arabic "No quick actions available"
      expect(find.text('لا توجد إجراءات سريعة'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 3: Quick Actions
  // ═══════════════════════════════════════════════════════════
  group('Quick Actions', () {
    testWidgets('quick action chip renders in preview', (tester) async {
      final actions = [
        DashboardQuickActionConfig(
          id: 'qa_test',
          labelKey: 'dqa_new_invoice',
          iconName: 'add_circle',
          route: '/invoices/create',
          position: 0,
        ),
      ];
      final config = _testConfig(actions: actions);
      await tester.pumpWidget(_app(
        DashboardPreview(configuration: config),
      ));
      await tester.pumpAndSettle();

      // Quick action label should render (English: "New Invoice")
      expect(find.text('New Invoice'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  Group 4: Different Templates
  // ═══════════════════════════════════════════════════════════
  group('Different Templates', () {
    for (final tpl in [
      DashboardTemplate.sales,
      DashboardTemplate.finance,
      DashboardTemplate.hr,
      DashboardTemplate.operations,
    ]) {
      testWidgets('${tpl.name} template preview renders', (tester) async {
        final config = _testConfig(template: tpl);
        await tester.pumpWidget(_app(
          DashboardPreview(configuration: config),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(DashboardPreview), findsOneWidget);
      });
    }
  });
}
