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

class ExpenseFeed {
  const ExpenseFeed(
    this.expenses, {
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final List<SharedExpense> expenses;
  final bool fromCache, pendingWrites;
  int get total =>
      expenses.fold(0, (total, expense) => total + expense.amountCents);
  int balanceFor(String uid) =>
      expenses.fold(0, (total, expense) => total + expense.balanceFor(uid));
}

abstract class ExpenseRepository {
  Stream<ExpenseFeed> watchExpenses(String groupId);
  Future<void> addExpense(String groupId, SharedExpense expense);
}

class FirestoreExpenseRepository implements ExpenseRepository {
  FirestoreExpenseRepository(this.firestore);
  final FirebaseFirestore firestore;
  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) => firestore
      .collection('groups')
      .doc(groupId)
      .collection('expenses')
      .orderBy('createdAt', descending: true)
      .snapshots(includeMetadataChanges: true)
      .map(
        (s) => ExpenseFeed(
          s.docs.map((d) => SharedExpense.fromMap(d.id, d.data())).toList(),
          fromCache: s.metadata.isFromCache,
          pendingWrites: s.metadata.hasPendingWrites,
        ),
      );
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
}
