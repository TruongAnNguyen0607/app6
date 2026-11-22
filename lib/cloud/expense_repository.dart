import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

int? parseCents(String value) {
  final text = value.trim();
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final amount =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return amount > 0 && amount <= 100000000 ? amount : null;
}

String dollars(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

class SharedExpense {
  SharedExpense({
    required this.id,
    required this.title,
    required this.amountCents,
    required this.payerId,
    required List<String> participantIds,
    required this.createdBy,
  }) : participantIds = List.unmodifiable(participantIds);
  final String id, title, payerId, createdBy;
  final int amountCents;
  final List<String> participantIds;

  factory SharedExpense.fromMap(String id, Map<String, dynamic> map) =>
      SharedExpense(
        id: id,
        title: map['title'] as String,
        amountCents: map['amountCents'] as int,
        payerId: map['payerId'] as String,
        participantIds: (map['participantIds'] as List).cast<String>(),
        createdBy: map['createdBy'] as String,
      );

  Map<String, int> get shares {
    final ids = participantIds.toSet().toList()..sort();
    if (ids.isEmpty) throw StateError('An expense requires participants');
    return {
      for (var i = 0; i < ids.length; i++)
        ids[i]:
            amountCents ~/ ids.length + (i < amountCents % ids.length ? 1 : 0),
    };
  }

  int balanceFor(String userId) =>
      (payerId == userId ? amountCents : 0) - (shares[userId] ?? 0);
}

/// A repayment from [fromId] (the debtor) to [toId] (the creditor).
class Settlement {
  const Settlement({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.amountCents,
    required this.createdBy,
  });
  final String id, fromId, toId, createdBy;
  final int amountCents;

  factory Settlement.fromMap(String id, Map<String, dynamic> map) =>
      Settlement(
        id: id,
        fromId: map['fromId'] as String,
        toId: map['toId'] as String,
        amountCents: map['amountCents'] as int,
        createdBy: map['createdBy'] as String,
      );

  /// Paying money moves the payer's balance up and the receiver's down.
  int balanceFor(String userId) =>
      (fromId == userId ? amountCents : 0) - (toId == userId ? amountCents : 0);
}

/// A suggested payment that moves the group toward zero balances.
class Transfer {
  const Transfer(this.fromId, this.toId, this.amountCents);
  final String fromId, toId;
  final int amountCents;
}

class ExpenseFeed {
  const ExpenseFeed(
    this.expenses, {
    this.settlements = const [],
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final List<SharedExpense> expenses;
  final List<Settlement> settlements;
  final bool fromCache, pendingWrites;
  int get total =>
      expenses.fold(0, (total, expense) => total + expense.amountCents);

  /// Net position: positive means the user is owed money, negative means
  /// they owe. Recorded settlements are included.
  int balanceFor(String uid) =>
      expenses.fold(0, (total, expense) => total + expense.balanceFor(uid)) +
      settlements.fold(0, (total, s) => total + s.balanceFor(uid));

  /// Fewest-payments plan that clears every balance. Deterministic: ties are
  /// broken by member ID so every device shows the same suggestions.
  List<Transfer> get transfers {
    final ids = <String>{
      for (final e in expenses) ...[e.payerId, ...e.participantIds],
      for (final s in settlements) ...[s.fromId, s.toId],
    };
    final debtors = <MapEntry<String, int>>[];
    final creditors = <MapEntry<String, int>>[];
    for (final id in ids) {
      final balance = balanceFor(id);
      if (balance < 0) debtors.add(MapEntry(id, -balance));
      if (balance > 0) creditors.add(MapEntry(id, balance));
    }
    int byAmountThenId(MapEntry<String, int> a, MapEntry<String, int> b) =>
        b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key);
    debtors.sort(byAmountThenId);
    creditors.sort(byAmountThenId);
    final owed = [for (final d in debtors) d.value];
    final due = [for (final c in creditors) c.value];
    final result = <Transfer>[];
    var i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      final amount = owed[i] < due[j] ? owed[i] : due[j];
      result.add(Transfer(debtors[i].key, creditors[j].key, amount));
      owed[i] -= amount;
      due[j] -= amount;
      if (owed[i] == 0) i++;
      if (due[j] == 0) j++;
    }
    return result;
  }
}

abstract class ExpenseRepository {
  Stream<ExpenseFeed> watchExpenses(String groupId);
  Future<void> addExpense(String groupId, SharedExpense expense);
}

/// Optional capability: repositories that can record repayments.
abstract class SettlementRepository {
  Future<void> addSettlement(String groupId, Settlement settlement);
}

class FirestoreExpenseRepository
    implements ExpenseRepository, SettlementRepository {
  FirestoreExpenseRepository(this.firestore);
  final FirebaseFirestore firestore;

  /// Combines the expenses and settlements collections into one feed so every
  /// balance in the app reflects repayments.
  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) {
    final group = firestore.collection('groups').doc(groupId);
    late final StreamController<ExpenseFeed> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? expensesSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? settlementsSub;
    QuerySnapshot<Map<String, dynamic>>? expenses, settlements;

    void emit() {
      final e = expenses, s = settlements;
      if (e == null || s == null) return;
      controller.add(
        ExpenseFeed(
          e.docs.map((d) => SharedExpense.fromMap(d.id, d.data())).toList(),
          settlements: s.docs
              .map((d) => Settlement.fromMap(d.id, d.data()))
              .toList(),
          fromCache: e.metadata.isFromCache || s.metadata.isFromCache,
          pendingWrites: e.metadata.hasPendingWrites ||
              s.metadata.hasPendingWrites,
        ),
      );
    }

    controller = StreamController<ExpenseFeed>(
      onListen: () {
        expensesSub = group
            .collection('expenses')
            .orderBy('createdAt', descending: true)
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              expenses = snapshot;
              emit();
            }, onError: controller.addError);
        settlementsSub = group
            .collection('settlements')
            .orderBy('createdAt', descending: true)
            .snapshots(includeMetadataChanges: true)
            .listen((snapshot) {
              settlements = snapshot;
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await expensesSub?.cancel();
        await settlementsSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> addExpense(String groupId, SharedExpense expense) {
    if (expense.title.trim().isEmpty ||
        expense.title.length > 80 ||
        expense.amountCents <= 0 ||
        expense.amountCents > 100000000 ||
        expense.participantIds.isEmpty ||
        !expense.participantIds.contains(expense.payerId)) {
      throw ArgumentError('Invalid expense');
    }
    return firestore
        .collection('groups')
        .doc(groupId)
        .collection('expenses')
        .doc(expense.id)
        .set({
          'title': expense.title.trim(),
          'amountCents': expense.amountCents,
          'payerId': expense.payerId,
          'participantIds': expense.participantIds,
          'createdBy': expense.createdBy,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Future<void> addSettlement(String groupId, Settlement settlement) {
    if (settlement.amountCents <= 0 ||
        settlement.amountCents > 100000000 ||
        settlement.fromId == settlement.toId) {
      throw ArgumentError('Invalid settlement');
    }
    return firestore
        .collection('groups')
        .doc(groupId)
        .collection('settlements')
        .doc(settlement.id)
        .set({
          'fromId': settlement.fromId,
          'toId': settlement.toId,
          'amountCents': settlement.amountCents,
          'createdBy': settlement.createdBy,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }
}
