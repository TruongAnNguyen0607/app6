import 'dart:async';

import 'package:app6/cloud/expense_repository.dart';
import 'package:app6/cloud/group_details.dart';
import 'package:app6/cloud/group_repository.dart';
import 'package:app6/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

SharedExpense expense(String payer, int cents, List<String> people) =>
    SharedExpense(
      id: '$payer$cents',
      title: 'Item',
      amountCents: cents,
      payerId: payer,
      participantIds: people,
      createdBy: payer,
    );

Settlement payment(String from, String to, int cents) => Settlement(
  id: '$from$to$cents',
  fromId: from,
  toId: to,
  amountCents: cents,
  createdBy: from,
);

class SettleRepository implements ExpenseRepository, SettlementRepository {
  final changes = StreamController<ExpenseFeed>.broadcast();
  final expenses = [
    expense('b', 1000, ['a', 'b']),
  ];
  final settlements = <Settlement>[];
  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) async* {
    yield ExpenseFeed(expenses, settlements: List.of(settlements));
    yield* changes.stream;
  }

  @override
  Future<void> addExpense(String groupId, SharedExpense expense) async {}

  @override
  Future<void> addSettlement(String groupId, Settlement settlement) async {
    settlements.add(settlement);
    changes.add(ExpenseFeed(expenses, settlements: List.of(settlements)));
  }
}

void main() {
  group('balances with settlements', () {
    test('a payment moves both balances toward zero and still sums to zero', () {
      final feed = ExpenseFeed(
        [
          expense('b', 1000, ['a', 'b']),
        ],
        settlements: [payment('a', 'b', 200)],
      );
      expect(feed.balanceFor('a'), -300);
      expect(feed.balanceFor('b'), 300);
      expect(feed.balanceFor('a') + feed.balanceFor('b'), 0);
    });

    test('full repayment settles everyone and suggests nothing', () {
      final feed = ExpenseFeed(
        [
          expense('b', 1000, ['a', 'b']),
        ],
        settlements: [payment('a', 'b', 500)],
      );
      expect(feed.balanceFor('a'), 0);
      expect(feed.balanceFor('b'), 0);
      expect(feed.transfers, isEmpty);
    });

    test('overpayment flips the direction of the debt', () {
      final feed = ExpenseFeed(
        [
          expense('b', 1000, ['a', 'b']),
        ],
        settlements: [payment('a', 'b', 700)],
      );
      final transfer = feed.transfers.single;
      expect(transfer.fromId, 'b');
      expect(transfer.toId, 'a');
      expect(transfer.amountCents, 200);
    });
  });

  group('suggested transfers', () {
    test('uses the fewest payments and clears every balance', () {
      // a paid 900 for everyone, b paid 300 for everyone; c owes both.
      final feed = ExpenseFeed([
        expense('a', 900, ['a', 'b', 'c']),
        expense('b', 300, ['a', 'b', 'c']),
      ]);
      final transfers = feed.transfers;
      expect(transfers.length, lessThanOrEqualTo(2));
      for (final id in ['a', 'b', 'c']) {
        final net =
            feed.balanceFor(id) +
            transfers
                .map(
                  (t) =>
                      (t.fromId == id ? t.amountCents : 0) -
                      (t.toId == id ? t.amountCents : 0),
                )
                .fold(0, (a, b) => a + b);
        expect(net, 0, reason: 'balance for $id after transfers');
      }
    });

    test('no expenses means no transfers', () {
      expect(const ExpenseFeed([]).transfers, isEmpty);
    });
  });

  group('Settle up screen', () {
    Future<SettleRepository> open(WidgetTester tester) async {
      final repository = SettleRepository();
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
      return repository;
    }

    testWidgets('shows who owes whom', (tester) async {
      await open(tester);
      expect(find.text('You owe Member 2 \$5.00'), findsOneWidget);
    });

    testWidgets('partial payment updates the balance, then full settles up', (
      tester,
    ) async {
      final repository = await open(tester);

      await tester.ensureVisible(find.text('Settle'));
      await tester.tap(find.text('Settle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '2.00');
      await tester.tap(find.text('Record payment').last);
      await tester.pumpAndSettle();

      expect(repository.settlements.single.amountCents, 200);
      expect(find.text('You owe Member 2 \$3.00'), findsOneWidget);
      expect(find.text('You paid Member 2'), findsOneWidget);

      await tester.ensureVisible(find.text('Settle'));
      await tester.tap(find.text('Settle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record payment').last);
      await tester.pumpAndSettle();

      expect(repository.settlements.length, 2);
      // The list was scrolled to reach the button, so include off-screen text.
      expect(
        find.text('Everyone is settled up.', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Settle'), findsNothing);
    });

    testWidgets('rejects an amount larger than what is owed', (tester) async {
      final repository = await open(tester);

      await tester.ensureVisible(find.text('Settle'));
      await tester.tap(find.text('Settle'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '9.00');
      await tester.tap(find.text('Record payment').last);
      await tester.pumpAndSettle();

      expect(find.text('Enter \$5.00 or less'), findsOneWidget);
      expect(repository.settlements, isEmpty);
    });
  });
}
