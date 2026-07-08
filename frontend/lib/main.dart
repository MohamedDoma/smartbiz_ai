import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'app/router.dart';
import 'core/l10n/app_localizations.dart';
import 'core/navigation/shell_state.dart';
import 'core/state/app_state.dart';
import 'core/theme/app_theme.dart';
import 'features/ai_chat/ai_chat_state.dart';
import 'features/advisor/advisor_state.dart';
import 'features/invoices/invoices_state.dart';
import 'features/onboarding/onboarding_state.dart';
import 'features/products/products_state.dart';
import 'core/api/product_service.dart';
import 'core/api/contact_service.dart';
import 'core/api/invoice_service.dart';
import 'core/api/payment_service.dart';
import 'core/api/warehouse_service.dart';
import 'core/api/inventory_service.dart';
import 'features/finance/finance_state.dart';
import 'features/employees/employees_state.dart';
import 'features/settings/settings_state.dart';
import 'features/customers/customers_state.dart';
import 'features/inventory/inventory_state.dart';
import 'features/payments/payments_state.dart';
import 'features/employees/roles_state.dart';
import 'features/employees/org_state.dart';
import 'features/employees/role_permission_state.dart';
import 'core/api/role_permission_service.dart';
import 'features/dashboard/dynamic_dashboard_state.dart';
import 'core/modules/workspace_module_state.dart';
import 'core/modules/blueprint_navigation_controller.dart';
import 'core/api/org_service.dart';
import 'features/employees/org_structure_state.dart';
import 'core/api/pipeline_service.dart';
import 'features/pipelines/pipeline_state.dart';
import 'core/api/document_service.dart';
import 'features/documents/document_state.dart';
import 'core/api/commission_service.dart';
import 'features/commissions/commission_state.dart';
import 'core/api/ownership_service.dart';
import 'features/ownership/ownership_state.dart';
import 'core/api/duplicate_service.dart';
import 'features/duplicates/duplicate_state.dart';
import 'core/api/report_service.dart';
import 'features/reports/report_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartBizApp());
}

class SmartBizApp extends StatelessWidget {
  const SmartBizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Essential — always needed at startup
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ShellState()),
        ChangeNotifierProvider(create: (_) => OnboardingState()),
        ChangeNotifierProvider(create: (_) => AiChatState()),
        // Heavy feature providers — lazy: created on first access only
        ChangeNotifierProvider(create: (_) => AdvisorState(), lazy: true),
        ChangeNotifierProxyProvider<AppState, InvoicesState>(
          create: (ctx) => InvoicesState(InvoiceService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, ProductsState>(
          create: (ctx) => ProductsState(ProductService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProvider(create: (_) => FinanceState(), lazy: true),
        ChangeNotifierProvider(create: (_) => EmployeesState(), lazy: true),
        ChangeNotifierProvider(create: (_) => SettingsState(), lazy: true),
        ChangeNotifierProxyProvider<AppState, CustomersState>(
          create: (ctx) => CustomersState(ContactService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, InventoryState>(
          create: (ctx) {
            final client = ctx.read<AppState>().apiClient;
            return InventoryState(WarehouseService(client), InventoryService(client));
          },
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, PaymentsState>(
          create: (ctx) => PaymentsState(PaymentService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProvider(create: (_) => RolesState(), lazy: true),
        ChangeNotifierProvider(create: (_) => OrgState(), lazy: true),
        ChangeNotifierProxyProvider<AppState, RolePermissionState>(
          create: (ctx) => RolePermissionState(RolePermissionService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, OrgStructureState>(
          create: (ctx) => OrgStructureState(OrgService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, PipelineState>(
          create: (ctx) => PipelineState(PipelineService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, DocumentState>(
          create: (ctx) => DocumentState(DocumentService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, CommissionState>(
          create: (ctx) => CommissionState(CommissionService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, OwnershipState>(
          create: (ctx) => OwnershipState(OwnershipService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, DuplicateState>(
          create: (ctx) => DuplicateState(DuplicateService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProxyProvider<AppState, ReportState>(
          create: (ctx) => ReportState(ReportService(ctx.read<AppState>().apiClient)),
          update: (_, __, prev) => prev!,
          lazy: true,
        ),
        ChangeNotifierProvider(create: (_) => DynamicDashboardState(), lazy: true),
        ChangeNotifierProvider(create: (_) => WorkspaceModuleState(), lazy: true),
        ChangeNotifierProvider(create: (_) => BlueprintNavigationController(), lazy: true),
      ],
      // Only rebuild the MaterialApp when locale or onboarding changes
      child: Selector<AppState, ({AppLanguage lang, Locale locale, bool onboarded})>(
        selector: (_, s) => (lang: s.uiLanguage, locale: s.locale, onboarded: s.isOnboardingCompleted),
        builder: (context, sel, _) {
          return AppLocaleProvider(
            language: sel.lang,
            child: MaterialApp.router(
              title: 'SmartBiz AI',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: sel.locale,
              supportedLocales: AppLanguage.values.map((l) => l.locale),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              routerConfig: buildAppRouter(context.read<AppState>()),
            ),
          );
        },
      ),
    );
  }
}

