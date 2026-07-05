import 'package:flutter_test/flutter_test.dart';

import 'package:isekai_strategem/src/app.dart';

void main() {
  testWidgets('Home screen shows the title and a Quick Battle entry point',
      (WidgetTester tester) async {
    await tester.pumpWidget(const IsekaiStrategemApp());

    expect(find.text('ISEKAI STRATEGEM'), findsOneWidget);
    expect(find.text('QUICK BATTLE (AI VS AI)'), findsOneWidget);
  });

  testWidgets('Quick Battle runs a real battle end to end and shows an outcome',
      (WidgetTester tester) async {
    await tester.pumpWidget(const IsekaiStrategemApp());

    await tester.tap(find.text('QUICK BATTLE (AI VS AI)'));
    await tester.pumpAndSettle();

    expect(find.text('Quick Battle'), findsOneWidget);
    expect(find.text('BATTLE LOG'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'SQUAD [AB] WINS|MUTUAL DEFEAT|NO CONCLUSION REACHED')),
      findsOneWidget,
    );

    await tester.tap(find.text('RUN ANOTHER BATTLE'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(RegExp(r'SQUAD [AB] WINS|MUTUAL DEFEAT|NO CONCLUSION REACHED')),
      findsOneWidget,
    );
  });
}
