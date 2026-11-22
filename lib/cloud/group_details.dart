import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'expense_repository.dart';
import 'group_repository.dart';
import 'invitation_repository.dart';
import 'invitation_widgets.dart';
import 'party_item_repository.dart';
import 'party_item_widgets.dart';

String memberLabel(SharedGroup group, String uid, String currentUser) =>
    uid == currentUser ? 'You' : 'Member ${group.memberIds.indexOf(uid) + 1}';
String balanceLabel(int cents) => cents == 0
    ? 'All settled up'
    : cents > 0
    ? 'You’re owed ${dollars(cents)}'
    : 'You owe ${dollars(-cents)}';
String transferLabel(SharedGroup group, Transfer t, String currentUser) {
  final from = memberLabel(group, t.fromId, currentUser);
  final to = memberLabel(group, t.toId, currentUser);
  return '$from ${t.fromId == currentUser ? 'owe' : 'owes'} $to ${dollars(t.amountCents)}';
}

class GroupDetailsPage extends StatefulWidget {
  const GroupDetailsPage({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
    this.invitations,
    this.partyItemRepository,
  });
  final SharedGroup group;
  final String userId;
  final ExpenseRepository repository;
  final InvitationRepository? invitations;
  final PartyItemRepository? partyItemRepository;
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

  SettlementRepository? get settlementRepository {
    final repository = widget.repository;
    return repository is SettlementRepository
        ? repository as SettlementRepository
        : null;
  }

  Future<void> settle(Transfer transfer) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SettleUpDialog(
      group: widget.group,
      userId: widget.userId,
      repository: settlementRepository!,
      transfer: transfer,
    ),
  );

  Future<void> add() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Sheet drag dismissal bypasses PopScope. Use the guarded Cancel/back
    // actions instead so a pending write cannot outlive a dismissed form.
    enableDrag: false,
    showDragHandle: false,
    isDismissible: false,
    builder: (_) => AddCloudExpense(
      group: widget.group,
      userId: widget.userId,
      repository: widget.repository,
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.group.name),
      actions: [
        if (widget.invitations != null && widget.group.ownerId == widget.userId)
          IconButton(
            tooltip: 'Invite members',
            icon: const Icon(Icons.person_add_alt_1),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => InviteMembersDialog(
                group: widget.group,
                userId: widget.userId,
                repository: widget.invitations!,
              ),
            ),
          ),
      ],
    ),
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
            const SizedBox(height: 20),
            Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE5E9E1)),
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9EEAE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.celebration_outlined,
                    color: Color(0xFF183D36),
                  ),
                ),
                title: const Text(
                  'Party Items & Checklist',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF183D36),
                  ),
                ),
                subtitle: const Text('Browse, select, and assign party items'),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF183D36),
                ),
                onTap: () {
                  final repo = widget.partyItemRepository ??
                      FirestorePartyItemRepository(
                        FirebaseFirestore.instance,
                      );
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PartyItemSelectionPage(
                        group: widget.group,
                        userId: widget.userId,
                        repository: repo,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            Text('Settle up', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            if (data.transfers.isEmpty)
              const Text('Everyone is settled up.')
            else
              for (final t in data.transfers)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(transferLabel(widget.group, t, widget.userId)),
                    trailing:
                        settlementRepository != null &&
                            (t.fromId == widget.userId ||
                                t.toId == widget.userId)
                        ? TextButton(
                            onPressed: () => settle(t),
                            child: const Text('Settle'),
                          )
                        : null,
                  ),
                ),
            if (data.settlements.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Payments', style: Theme.of(context).textTheme.titleMedium),
              for (final s in data.settlements)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(
                    '${memberLabel(widget.group, s.fromId, widget.userId)} paid ${memberLabel(widget.group, s.toId, widget.userId)}',
                  ),
                  trailing: Text(dollars(s.amountCents)),
                ),
            ],
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
                'Only you are in this group. Expenses will be saved, but there is no shared debt until other members join. The group owner can invite others using the invite button above.',
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
    if (saving) return;
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
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
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

/// Records a full or partial repayment toward a suggested [Transfer].
class SettleUpDialog extends StatefulWidget {
  const SettleUpDialog({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
    required this.transfer,
  });
  final SharedGroup group;
  final String userId;
  final SettlementRepository repository;
  final Transfer transfer;
  @override
  State<SettleUpDialog> createState() => _SettleUpDialogState();
}

class _SettleUpDialogState extends State<SettleUpDialog> {
  late final amount = TextEditingController(
    text: (widget.transfer.amountCents / 100).toStringAsFixed(2),
  );
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  // One ID per dialog prevents duplicate writes from repeated taps.
  final id = base64UrlEncode(
    List<int>.generate(18, (_) => Random.secure().nextInt(256)),
  );

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  String? validate(String? value) {
    final cents = parseCents(value ?? '');
    if (cents == null) return 'Enter an amount with up to 2 decimal places';
    if (cents > widget.transfer.amountCents) {
      return 'Enter ${dollars(widget.transfer.amountCents)} or less';
    }
    return null;
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.addSettlement(
        widget.group.id,
        Settlement(
          id: id,
          fromId: widget.transfer.fromId,
          toId: widget.transfer.toId,
          amountCents: parseCents(amount.text)!,
          createdBy: widget.userId,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save. Check your connection and confirm the updated database rules are published.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Record payment'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(transferLabel(widget.group, widget.transfer, widget.userId)),
            const SizedBox(height: 12),
            TextFormField(
              controller: amount,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount paid (USD)',
                helperText: 'Lower the amount to record a partial payment',
              ),
              validator: validate,
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'Saving…' : 'Record payment'),
        ),
      ],
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
