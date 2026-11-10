import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'expense_repository.dart';
import 'group_repository.dart';

String memberLabel(SharedGroup group, String uid, String currentUser) =>
    uid == currentUser ? 'You' : 'Member ${group.memberIds.indexOf(uid) + 1}';
String balanceLabel(int cents) => cents == 0
    ? 'All settled up'
    : cents > 0
    ? 'You’re owed ${dollars(cents)}'
    : 'You owe ${dollars(-cents)}';

class GroupDetailsPage extends StatefulWidget {
  const GroupDetailsPage({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
  });
  final SharedGroup group;
  final String userId;
  final ExpenseRepository repository;
  @override
  State<GroupDetailsPage> createState() => _GroupDetailsPageState();
}

class _GroupDetailsPageState extends State<GroupDetailsPage> {
  late Stream<ExpenseFeed> feed;
  @override
  void initState() {
    super.initState();
    feed = widget.repository.watchExpenses(widget.group.id);
  }

  Future<void> add() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AddCloudExpense(
      group: widget.group,
      userId: widget.userId,
      repository: widget.repository,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.group.name)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: add,
      icon: const Icon(Icons.add),
      label: const Text('Add expense'),
    ),
    body: StreamBuilder<ExpenseFeed>(
      stream: feed,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Expenses could not be loaded. Check your connection. The app owner may need to publish the updated database rules.',
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => feed = widget.repository.watchExpenses(
                        widget.group.id,
                      ),
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 110),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF183D36),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Group spending • USD',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dollars(data.total),
                    style: const TextStyle(
                      fontSize: 36,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    balanceLabel(data.balanceFor(widget.userId)),
                    style: const TextStyle(
                      color: Color(0xFFD9EEAE),
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              data.pendingWrites
                  ? 'Changes waiting to sync'
                  : data.fromCache
                  ? 'Showing saved expenses • cloud not confirmed'
                  : 'Up to date',
            ),
            const SizedBox(height: 24),
            Text(
              'Members & balances',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            for (final uid in widget.group.memberIds)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(memberLabel(widget.group, uid, widget.userId)),
                subtitle: Text(uid == widget.userId ? 'Your account' : uid),
                trailing: Text(
                  data.balanceFor(uid) == 0
                      ? 'Settled'
                      : '${data.balanceFor(uid) > 0 ? '+' : '−'}${dollars(data.balanceFor(uid).abs())}',
                ),
              ),
            if (widget.group.memberIds.length == 1)
              const Text(
                'Only you are in this group. Expenses will be saved, but there is no shared debt until other members join. Invitations are coming next.',
              ),
            const SizedBox(height: 28),
            Text('Expenses', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            if (data.expenses.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No expenses yet. Add your first expense below.'),
              ),
            for (final expense in data.expenses)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(expense.title),
                  subtitle: Text(
                    '${memberLabel(widget.group, expense.payerId, widget.userId)} paid • ${expense.participantIds.length} participant(s)\nYour share: ${dollars(expense.shares[widget.userId] ?? 0)}',
                  ),
                  trailing: Text(dollars(expense.amountCents)),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class AddCloudExpense extends StatefulWidget {
  const AddCloudExpense({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
  });
  final SharedGroup group;
  final String userId;
  final ExpenseRepository repository;
  @override
  State<AddCloudExpense> createState() => _AddCloudExpenseState();
}

class _AddCloudExpenseState extends State<AddCloudExpense> {
  final title = TextEditingController(), amount = TextEditingController();
  final form = GlobalKey<FormState>();
  late String payer;
  late Set<String> participants;
  bool saving = false;
  String? error;
  // One ID per form prevents duplicate writes from repeated submissions.
  final id = base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );
  @override
  void initState() {
    super.initState();
    payer = widget.userId;
    participants = widget.group.memberIds.toSet();
  }

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (participants.isEmpty || !participants.contains(payer)) {
      setState(() => error = 'Include the payer and at least one participant.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.addExpense(
        widget.group.id,
        SharedExpense(
          id: id,
          title: title.text.trim(),
          amountCents: parseCents(amount.text)!,
          payerId: payer,
          participantIds: participants.toList(),
          createdBy: widget.userId,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Could not save. Check your connection and confirm the updated database rules are published.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add an expense',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: title,
              enabled: !saving,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'What was it for?'),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter an expense name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount (USD)'),
              validator: (v) => parseCents(v ?? '') == null
                  ? 'Enter 0.01–1,000,000 with up to 2 decimal places'
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: payer,
              decoration: const InputDecoration(labelText: 'Paid by'),
              items: widget.group.memberIds
                  .map(
                    (uid) => DropdownMenuItem(
                      value: uid,
                      child: Text(
                        memberLabel(widget.group, uid, widget.userId),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) => setState(() {
                      payer = value!;
                      participants.add(payer);
                    }),
            ),
            const SizedBox(height: 16),
            const Text('Split equally between'),
            for (final uid in widget.group.memberIds)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(memberLabel(widget.group, uid, widget.userId)),
                value: participants.contains(uid),
                onChanged: saving || uid == payer
                    ? null
                    : (v) => setState(() {
                        if (v!) {
                          participants.add(uid);
                        } else {
                          participants.remove(uid);
                        }
                      }),
              ),
            const Text(
              'Any leftover cents are assigned consistently by member ID. The payer is included in the split.',
              style: TextStyle(fontSize: 12),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(
                saving ? 'Waiting for cloud confirmation…' : 'Save expense',
              ),
            ),
            if (saving)
              const Text(
                'Offline changes will sync when your connection returns.',
              ),
          ],
        ),
      ),
    ),
  );
}

class GroupSummary extends StatefulWidget {
  const GroupSummary({
    super.key,
    required this.groupId,
    required this.userId,
    required this.repository,
  });
  final String groupId, userId;
  final ExpenseRepository repository;
  @override
  State<GroupSummary> createState() => _GroupSummaryState();
}

class _GroupSummaryState extends State<GroupSummary> {
  late final feed = widget.repository.watchExpenses(widget.groupId);
  @override
  Widget build(BuildContext context) => StreamBuilder<ExpenseFeed>(
    stream: feed,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Text('Expenses unavailable • open group to retry');
      }
      if (!snapshot.hasData) return const Text('Loading balance…');
      final data = snapshot.data!;
      return Text(
        '${balanceLabel(data.balanceFor(widget.userId))}\n${dollars(data.total)} spent${data.pendingWrites
            ? ' • syncing'
            : data.fromCache
            ? ' • cached'
            : ''}',
      );
    },
  );
}
