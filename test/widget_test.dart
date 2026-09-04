import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:arrive_alert/main.dart';

void main() {
  testWidgets('App builds and shows the destination search', (tester) async {
    await tester.pumpWidget(const ArriveAlertApp());
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Buscar destino (o toca el mapa)'), findsOneWidget);
  });
}
