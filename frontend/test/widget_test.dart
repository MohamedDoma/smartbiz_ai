import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/main.dart';

void main() {
  testWidgets('App renders without exceptions', (tester) async {
    await tester.pumpWidget(const SmartBizApp());

    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}