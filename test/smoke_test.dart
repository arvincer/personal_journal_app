import 'package:flutter_test/flutter_test.dart';
import 'package:personal_journal_app/app/journal_app.dart';

void main() {
  testWidgets('bootstrap renders today', (tester) async {
    await tester.pumpWidget(JournalApp.bootstrapForTest());

    expect(find.text('今天'), findsOneWidget);
  });
}
