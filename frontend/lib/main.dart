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
import 'features/finance/finance_state.dart';
import 'features/employees/employees_state.dart';
import 'features/settings/settings_state.dart';
import 'features/customers/customers_state.dart';
import 'features/inventory/inventory_state.dart';
import 'features/payments/payments_state.dart';
import 'features/employees/roles_state.dart';
import 'features/employees/org_state.dart';
import 'features/dashboard/dynamic_dashboard_state.dart';
import 'core/modules/workspace_module_state.dart';
import 'core/modules/blueprint_navigation_controller.dart';

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
        ChangeNotifierProvider(create: (_) => InvoicesState(), lazy: true),
        ChangeNotifierProvider(create: (_) => ProductsState(), lazy: true),
        ChangeNotifierProvider(create: (_) => FinanceState(), lazy: true),
        ChangeNotifierProvider(create: (_) => EmployeesState(), lazy: true),
        ChangeNotifierProvider(create: (_) => SettingsState(), lazy: true),
        ChangeNotifierProvider(create: (_) => CustomersState(), lazy: true),
        ChangeNotifierProvider(create: (_) => InventoryState(), lazy: true),
        ChangeNotifierProvider(create: (_) => PaymentsState(), lazy: true),
        ChangeNotifierProvider(create: (_) => RolesState(), lazy: true),
        ChangeNotifierProvider(create: (_) => OrgState(), lazy: true),
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

