import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('material test harness renders a widget', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('今天')));

    expect(find.text('今天'), findsOneWidget);
  });
}
