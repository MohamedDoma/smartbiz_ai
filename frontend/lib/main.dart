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
import 'features/employees/roles_state.dart';
import 'features/employees/org_state.dart';

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
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => ShellState()),
        ChangeNotifierProvider(create: (_) => OnboardingState()),
        ChangeNotifierProvider(create: (_) => AiChatState()),
        ChangeNotifierProvider(create: (_) => AdvisorState()),
        ChangeNotifierProvider(create: (_) => InvoicesState()),
        ChangeNotifierProvider(create: (_) => ProductsState()),
        ChangeNotifierProvider(create: (_) => FinanceState()),
        ChangeNotifierProvider(create: (_) => EmployeesState()),
        ChangeNotifierProvider(create: (_) => SettingsState()),
        ChangeNotifierProvider(create: (_) => CustomersState()),
        ChangeNotifierProvider(create: (_) => InventoryState()),
        ChangeNotifierProvider(create: (_) => RolesState()),
        ChangeNotifierProvider(create: (_) => OrgState()),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          return AppLocaleProvider(
            language: appState.uiLanguage,
            child: MaterialApp.router(
              title: 'SmartBiz AI',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              locale: appState.locale,
              supportedLocales: AppLanguage.values.map((l) => l.locale),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              routerConfig: buildAppRouter(appState),
            ),
          );
        },
      ),
    );
  }
}
