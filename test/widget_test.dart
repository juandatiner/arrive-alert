import 'package:flutter_test/flutter_test.dart';

import 'package:arrive_alert/main.dart';

void main() {
  testWidgets('App builds and shows home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ArriveAlertApp());
    await tester.pump();

    expect(find.text('Aviso de llegada'), findsOneWidget);
  });
}
