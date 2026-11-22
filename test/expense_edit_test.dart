import 'dart:async';

import 'package:app6/cloud/expense_repository.dart';
import 'package:app6/cloud/group_details.dart';
import 'package:app6/cloud/group_repository.dart';
import 'package:app6/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const tripGroup = SharedGroup(
  id: 'g1',
  name: 'Trip',
  ownerId: 'a',
  memberIds: ['a', 'b', 'c'],
);

SharedExpense expense(String id, String title, int cents, String createdBy) =>
    SharedExpense(
      id: id,
      title: title,
      amountCents: cents,
      payerId: createdBy,
      participantIds: const ['a', 'b', 'c'],
      createdBy: createdBy,
    );

class EditableExpenses implements ExpenseRepository, ExpenseEditRepository {
  final changes = StreamController<ExpenseFeed>.broadcast();
  final expenses = [
    expense('e1', 'Dinner', 3000, 'b'),
    expense('e2', 'Taxi', 1200, 'a'),
  ];
  final activity = <ExpenseActivity>[];
  bool failDelete = false;

  ExpenseFeed get feed =>
      ExpenseFeed(List.of(expenses), activity: List.of(activity));

  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) async* {
    yield feed;
    yield* changes.stream;
  }

  @override
  Future<void> addExpense(String groupId, SharedExpense expense) async {}

  @override
  Future<void> updateExpense(
    String groupId,
    SharedExpense updated, {
    required SharedExpense previous,
    required String actorId,
  }) async {
    final index = expenses.indexWhere((e) => e.id == previous.id);
    expenses[index] = SharedExpense(
      id: previous.id,
      title: updated.title,
      amountCents: updated.amountCents,
      payerId: updated.payerId,
      participantIds: updated.participantIds,
      createdBy: previous.createdBy,
      updatedBy: actorId,
    );
    activity.insert(
      0,
      ExpenseActivity(
        id: 'act${activity.length}',
        type: ActivityType.edited,
        expenseId: previous.id,
        title: updated.title,
        amountCents: updated.amountCents,
        actorId: actorId,
        previousTitle: previous.title,
        previousAmountCents: previous.amountCents,
      ),
    );
    changes.add(feed);
  }

  @override
  Future<void> deleteExpense(
    String groupId,
    SharedExpense expense, {
    required String actorId,
  }) async {
    if (failDelete) throw StateError('Permission denied');
    expenses.removeWhere((e) => e.id == expense.id);
    activity.insert(
      0,
      ExpenseActivity(
        id: 'act${activity.length}',
        type: ActivityType.deleted,
        expenseId: expense.id,
        title: expense.title,
        amountCents: expense.amountCents,
        actorId: actorId,
      ),
    );
    changes.add(feed);
  }
}

void main() {
  group('permissions', () {
    test('creator and group owner may modify, other members may not', () {
      final e = expense('e1', 'Dinner', 3000, 'b');
      expect(canModifyExpense(e, tripGroup, 'b'), isTrue, reason: 'creator');
      expect(canModifyExpense(e, tripGroup, 'a'), isTrue, reason: 'owner');
      expect(canModifyExpense(e, tripGroup, 'c'), isFalse, reason: 'other member');
    });
  });

  group('activity labels', () {
    test('describe who did what, including the previous values', () {
      const edited = ExpenseActivity(
        id: '1',
        type: ActivityType.edited,
        expenseId: 'e1',
        title: 'Team dinner',
        amountCents: 4500,
        actorId: 'b',
        previousTitle: 'Dinner',
        previousAmountCents: 3000,
      );
      expect(
        activityLabel(tripGroup, edited, 'b'),
        'You edited "Team dinner" (\$45.00) • was "Dinner" \$30.00',
      );
      const amountOnly = ExpenseActivity(
        id: '2',
        type: ActivityType.edited,
        expenseId: 'e1',
        title: 'Dinner',
        amountCents: 4000,
        actorId: 'c',
        previousTitle: 'Dinner',
        previousAmountCents: 3000,
      );
      expect(
        activityLabel(tripGroup, amountOnly, 'b'),
        'Member 3 edited "Dinner" (\$40.00) • was \$30.00',
      );
      const deleted = ExpenseActivity(
        id: '3',
        type: ActivityType.deleted,
        expenseId: 'e1',
        title: 'Dinner',
        amountCents: 3000,
        actorId: 'a',
      );
      expect(
        activityLabel(tripGroup, deleted, 'b'),
        'Member 1 deleted "Dinner" (\$30.00)',
      );
    });
  });

  group('Expense screen', () {
    Future<EditableExpenses> open(WidgetTester tester, String userId) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = EditableExpenses();
      await tester.pumpWidget(
        MyApp(
          home: GroupDetailsPage(
            group: tripGroup,
            userId: userId,
            repository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    final actions = find.byTooltip('Expense actions');

    testWidgets('a member who is neither creator nor owner gets no actions', (
      tester,
    ) async {
      await open(tester, 'c');
      expect(actions, findsNothing);
    });

    testWidgets('a creator can act only on their own expense', (tester) async {
      await open(tester, 'b');
      expect(actions, findsOneWidget);
    });

    testWidgets('the group owner can act on every expense', (tester) async {
      await open(tester, 'a');
      expect(actions, findsNWidgets(2));
    });

    testWidgets('editing updates the expense and records it in activity', (
      tester,
    ) async {
      await open(tester, 'b');
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      // The form opens pre-filled with the current values.
      expect(find.text('Edit expense'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Dinner'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '30.00'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Team dinner');
      await tester.enterText(find.byType(TextFormField).at(1), '45');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      expect(find.text('Team dinner'), findsOneWidget);
      expect(find.textContaining('Edited'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(
        find.text(
          'You edited "Team dinner" (\$45.00) • was "Dinner" \$30.00',
        ),
        findsOneWidget,
      );
    });

    testWidgets('deleting asks first, then removes it and logs it', (
      tester,
    ) async {
      final repository = await open(tester, 'b');
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete expense?'), findsOneWidget);
      // Cancelling changes nothing.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repository.expenses.length, 2);

      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.expenses.map((e) => e.id), ['e2']);
      expect(find.text('Dinner'), findsNothing);
      expect(find.text('You deleted "Dinner" (\$30.00)'), findsOneWidget);
    });

    testWidgets('a rejected delete keeps the expense and tells the user', (
      tester,
    ) async {
      final repository = await open(tester, 'b');
      repository.failDelete = true;
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not delete'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
    });
  });
}
