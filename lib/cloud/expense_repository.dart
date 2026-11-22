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
    this.updatedBy,
  }) : participantIds = List.unmodifiable(participantIds);
  final String id, title, payerId, createdBy;

  /// Set once the expense has been edited after it was created.
  final String? updatedBy;
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
        updatedBy: map['updatedBy'] as String?,
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

enum ActivityType { created, edited, deleted }

/// One entry in the group's append-only expense history. Titles and amounts
/// are snapshots, so entries stay readable after an expense is deleted.
class ExpenseActivity {
  const ExpenseActivity({
    required this.id,
    required this.type,
    required this.expenseId,
    required this.title,
    required this.amountCents,
    required this.actorId,
    this.previousTitle,
    this.previousAmountCents,
    this.createdAt,
  });
  final String id, expenseId, title, actorId;
  final ActivityType type;
  final int amountCents;
  final String? previousTitle;
  final int? previousAmountCents;

  /// Null while the server timestamp is still pending.
  final DateTime? createdAt;

  factory ExpenseActivity.fromMap(String id, Map<String, dynamic> map) =>
      ExpenseActivity(
        id: id,
        type: ActivityType.values.firstWhere(
          (t) => t.name == map['type'],
          orElse: () => ActivityType.edited,
        ),
        expenseId: map['expenseId'] as String,
        title: map['title'] as String,
        amountCents: map['amountCents'] as int,
        actorId: map['actorId'] as String,
        previousTitle: map['previousTitle'] as String?,
        previousAmountCents: map['previousAmountCents'] as int?,
        createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      );
}

class ExpenseFeed {
  const ExpenseFeed(
    this.expenses, {
    this.settlements = const [],
    this.activity = const [],
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final List<SharedExpense> expenses;
  final List<Settlement> settlements;
  final List<ExpenseActivity> activity;
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

/// Optional capability: repositories that can correct or remove expenses.
/// Every change also appends an entry to the group's activity history.
abstract class ExpenseEditRepository {
  /// Replaces the editable fields of [previous] with those of [updated].
  Future<void> updateExpense(
    String groupId,
    SharedExpense updated, {
    required SharedExpense previous,
    required String actorId,
  });
  Future<void> deleteExpense(
    String groupId,
    SharedExpense expense, {
    required String actorId,
  });
}

class FirestoreExpenseRepository
    implements ExpenseRepository, SettlementRepository, ExpenseEditRepository {
  FirestoreExpenseRepository(this.firestore);
  final FirebaseFirestore firestore;

  /// Combines expenses, settlements and activity into one feed so every
  /// balance and history entry in the app stays consistent.
  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) {
    final group = firestore.collection('groups').doc(groupId);
    late final StreamController<ExpenseFeed> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    QuerySnapshot<Map<String, dynamic>>? expenses, settlements, activity;

    void emit() {
      final e = expenses, s = settlements, a = activity;
      if (e == null || s == null || a == null) return;
      controller.add(
        ExpenseFeed(
          e.docs.map((d) => SharedExpense.fromMap(d.id, d.data())).toList(),
          settlements: s.docs
              .map((d) => Settlement.fromMap(d.id, d.data()))
              .toList(),
          activity: a.docs
              .map((d) => ExpenseActivity.fromMap(d.id, d.data()))
              .toList(),
          fromCache:
              e.metadata.isFromCache ||
              s.metadata.isFromCache ||
              a.metadata.isFromCache,
          pendingWrites:
              e.metadata.hasPendingWrites ||
              s.metadata.hasPendingWrites ||
              a.metadata.hasPendingWrites,
        ),
      );
    }

    Stream<QuerySnapshot<Map<String, dynamic>>> newestFirst(
      String name, [
      int? limit,
    ]) {
      var query = group
          .collection(name)
          .orderBy('createdAt', descending: true);
      if (limit != null) query = query.limit(limit);
      return query.snapshots(includeMetadataChanges: true);
    }

    controller = StreamController<ExpenseFeed>(
      onListen: () {
        subscriptions.addAll([
          newestFirst('expenses').listen((snapshot) {
            expenses = snapshot;
            emit();
          }, onError: controller.addError),
          newestFirst('settlements').listen((snapshot) {
            settlements = snapshot;
            emit();
          }, onError: controller.addError),
          newestFirst('activity', 50).listen((snapshot) {
            activity = snapshot;
            emit();
          }, onError: controller.addError),
        ]);
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );
    return controller.stream;
  }

  Map<String, Object?> _activity({
    required ActivityType type,
    required String expenseId,
    required String title,
    required int amountCents,
    required String actorId,
    String? previousTitle,
    int? previousAmountCents,
  }) => {
    'type': type.name,
    'expenseId': expenseId,
    'title': title,
    'amountCents': amountCents,
    'actorId': actorId,
    'previousTitle': ?previousTitle,
    'previousAmountCents': ?previousAmountCents,
    'createdAt': FieldValue.serverTimestamp(),
  };

  void _validate(SharedExpense expense) {
    if (expense.title.trim().isEmpty ||
        expense.title.trim().length > 80 ||
        expense.amountCents <= 0 ||
        expense.amountCents > 100000000 ||
        expense.participantIds.isEmpty ||
        !expense.participantIds.contains(expense.payerId)) {
      throw ArgumentError('Invalid expense');
    }
  }

  @override
  Future<void> addExpense(String groupId, SharedExpense expense) {
    _validate(expense);
    final group = firestore.collection('groups').doc(groupId);
    // One batch keeps the expense and its history entry in step. The history ID
    // is derived from the expense ID so a retried submit cannot log it twice.
    final batch = firestore.batch()
      ..set(group.collection('expenses').doc(expense.id), {
        'title': expense.title.trim(),
        'amountCents': expense.amountCents,
        'payerId': expense.payerId,
        'participantIds': expense.participantIds,
        'createdBy': expense.createdBy,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(
        group.collection('activity').doc('${expense.id}-created'),
        _activity(
          type: ActivityType.created,
          expenseId: expense.id,
          title: expense.title.trim(),
          amountCents: expense.amountCents,
          actorId: expense.createdBy,
        ),
      );
    return batch.commit();
  }

  @override
  Future<void> updateExpense(
    String groupId,
    SharedExpense updated, {
    required SharedExpense previous,
    required String actorId,
  }) {
    _validate(updated);
    final group = firestore.collection('groups').doc(groupId);
    final batch = firestore.batch()
      ..update(group.collection('expenses').doc(previous.id), {
        'title': updated.title.trim(),
        'amountCents': updated.amountCents,
        'payerId': updated.payerId,
        'participantIds': updated.participantIds,
        'updatedBy': actorId,
        'updatedAt': FieldValue.serverTimestamp(),
      })
      ..set(
        group.collection('activity').doc(),
        _activity(
          type: ActivityType.edited,
          expenseId: previous.id,
          title: updated.title.trim(),
          amountCents: updated.amountCents,
          actorId: actorId,
          previousTitle: previous.title,
          previousAmountCents: previous.amountCents,
        ),
      );
    return batch.commit();
  }

  @override
  Future<void> deleteExpense(
    String groupId,
    SharedExpense expense, {
    required String actorId,
  }) {
    final group = firestore.collection('groups').doc(groupId);
    final batch = firestore.batch()
      ..delete(group.collection('expenses').doc(expense.id))
      ..set(
        group.collection('activity').doc(),
        _activity(
          type: ActivityType.deleted,
          expenseId: expense.id,
          title: expense.title,
          amountCents: expense.amountCents,
          actorId: actorId,
        ),
      );
    return batch.commit();
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
