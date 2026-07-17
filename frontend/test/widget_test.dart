import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartbiz_ai/main.dart';

void main() {
  testWidgets('App renders without exceptions', (tester) async {
    // Provide mock SharedPreferences to avoid MissingPluginException.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const SmartBizApp());

    // Pump past the splash screen auto-navigation timer (typically ~2s).
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}