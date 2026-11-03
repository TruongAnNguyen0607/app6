import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app6/main.dart';

void main() {
  testWidgets('Dashboard renders and an expense updates the balance', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1100);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MyApp());
    expect(find.text('Good things, shared.'), findsOneWidget);
    expect(find.text('+\$55.40'), findsOneWidget);
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Museum tickets');
    await tester.enterText(find.byType(TextFormField).at(1), '40');
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.text('Museum tickets'), findsOneWidget);
    expect(find.text('+\$85.40'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Mobile navigation and form validation work', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MyApp());
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Goals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add contribution'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-20');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Add contribution').last,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Enter an amount between 0.01 and 1,000,000'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField), '80');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Add contribution').last,
    );
    await tester.pumpAndSettle();
    expect(find.text('\$800.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
