import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app/router.dart';
import 'core/navigation/shell_state.dart';
import 'core/theme/app_theme.dart';

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
        ChangeNotifierProvider(create: (_) => ShellState()),
      ],
      child: MaterialApp.router(
        title: 'SmartBiz AI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: appRouter,
      ),
    );
  }
}
