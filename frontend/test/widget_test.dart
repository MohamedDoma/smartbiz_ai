import 'package:flutter_test/flutter_test.dart';
import 'package:smartbiz_ai/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartBizApp());
    await tester.pumpAndSettle();
    expect(find.text('SmartBiz'), findsOneWidget);
  });
}
