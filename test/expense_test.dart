import 'dart:async';

import 'package:app6/cloud/expense_repository.dart';
import 'package:app6/cloud/group_repository.dart';
import 'package:app6/cloud/group_details.dart';
import 'package:app6/cloud/cloud_home.dart';
import 'package:app6/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeExpenses implements ExpenseRepository {
  final changes = StreamController<ExpenseFeed>.broadcast();
  final saved = <SharedExpense>[];
  bool fail = false;
  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) async* {
    yield ExpenseFeed(List.of(saved));
    yield* changes.stream;
  }

  @override
  Future<void> addExpense(String groupId, SharedExpense expense) async {
    if (fail) throw StateError('Permission denied');
    saved.add(expense);
    changes.add(ExpenseFeed(List.of(saved)));
  }
}

class TestGroupRepository implements GroupRepository {
  @override
  Stream<GroupFeed> watchGroups(String userId) => Stream.value(
    const GroupFeed(
      [
        SharedGroup(
          id: 'g1',
          name: 'Saturday party',
          ownerId: 'a',
          memberIds: ['a'],
        ),
      ],
      fromCache: false,
      pendingWrites: false,
    ),
  );
  @override
  Future<void> createGroup(String userId, String name) async {}
}

void main() {
  testWidgets('Phone dashboard opens the selected group', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final expenses = FakeExpenses();
    addTearDown(expenses.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: CloudGroupsPage(
          userId: 'a',
          repository: TestGroupRepository(),
          expenseRepository: expenses,
          onSignOut: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Saturday party'));
    await tester.tap(find.text('Saturday party'));
    await tester.pumpAndSettle();
    expect(find.text('Members & balances'), findsOneWidget);
    expect(find.text('Add expense'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('Amounts parse exactly and reject invalid or oversized input', () {
    expect(parseCents('10.01'), 1001);
    expect(parseCents('0.01'), 1);
    expect(parseCents(' 2.5 '), 250);
    for (final invalid in ['0', '-1', 'NaN', '1.001', '1000000.01', '1e2']) {
      expect(parseCents(invalid), isNull);
    }
  });
  test('Uneven splits conserve cents and balances sum to zero', () {
    final expense = SharedExpense(
      id: 'e1',
      title: 'Dinner',
      amountCents: 1000,
      payerId: 'b',
      participantIds: ['c', 'b', 'a'],
      createdBy: 'a',
    );
    expect(expense.shares, {'a': 334, 'b': 333, 'c': 333});
    expect(expense.balanceFor('b'), 667);
    expect(
      expense.balanceFor('a') +
          expense.balanceFor('b') +
          expense.balanceFor('c'),
      0,
    );
    expect(expense.balanceFor('outsider'), 0);
  });
  test('One-member spending creates no shared debt', () {
    final expense = SharedExpense(
      id: 'e1',
      title: 'Food',
      amountCents: 1001,
      payerId: 'a',
      participantIds: ['a'],
      createdBy: 'a',
    );
    expect(ExpenseFeed([expense]).total, 1001);
    expect(expense.balanceFor('a'), 0);
  });
  testWidgets('Add expense updates group spending, share and balance', (
    tester,
  ) async {
    final repository = FakeExpenses();
    addTearDown(repository.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: GroupDetailsPage(
          group: const SharedGroup(
            id: 'g1',
            name: 'Trip',
            ownerId: 'a',
            memberIds: ['a', 'b'],
          ),
          userId: 'a',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add expense'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Dinner');
    await tester.enterText(find.byType(TextFormField).at(1), '10.01');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.amountCents, 1001);
    expect(find.text('You’re owed \$5.00'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Failed expense write keeps form available for retry', (
    tester,
  ) async {
    final repository = FakeExpenses()..fail = true;
    addTearDown(repository.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: Scaffold(
          body: AddCloudExpense(
            group: const SharedGroup(
              id: 'g1',
              name: 'Trip',
              ownerId: 'a',
              memberIds: ['a'],
            ),
            userId: 'a',
            repository: repository,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'Dinner');
    await tester.enterText(find.byType(TextFormField).at(1), '12');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save.'), findsOneWidget);
    expect(repository.saved, isEmpty);
    expect(find.text('Dinner'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
