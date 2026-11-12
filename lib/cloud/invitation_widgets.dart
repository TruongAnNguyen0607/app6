import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'group_repository.dart';
import 'invitation_repository.dart';
import 'expense_repository.dart';
import 'group_details.dart';

class LiveGroupDetails extends StatefulWidget {
  const LiveGroupDetails({
    super.key,
    required this.group,
    required this.userId,
    required this.expenses,
    required this.invitations,
  });
  final SharedGroup group;
  final String userId;
  final ExpenseRepository expenses;
  final InvitationRepository invitations;
  @override
  State<LiveGroupDetails> createState() => _LiveGroupDetailsState();
}

class _LiveGroupDetailsState extends State<LiveGroupDetails> {
  late Stream<SharedGroup?> group;
  @override
  void initState() {
    super.initState();
    group = widget.invitations.watchGroup(widget.group.id);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<SharedGroup?>(
    stream: group,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          (snapshot.connectionState != ConnectionState.waiting &&
              snapshot.data == null)) {
        return Scaffold(
          appBar: AppBar(title: const Text('Group unavailable')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Unable to access this group. Check your connection or contact the owner.',
                  ),
                ),
                TextButton(
                  onPressed: () => setState(
                    () =>
                        group = widget.invitations.watchGroup(widget.group.id),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return GroupDetailsPage(
        group: snapshot.data!,
        userId: widget.userId,
        repository: widget.expenses,
        invitations: widget.invitations,
      );
    },
  );
}

class JoinGroupDialog extends StatefulWidget {
  const JoinGroupDialog({
    super.key,
    required this.repository,
    required this.userId,
  });
  final InvitationRepository repository;
  final String userId;
  @override
  State<JoinGroupDialog> createState() => _JoinGroupDialogState();
}

class _JoinGroupDialogState extends State<JoinGroupDialog> {
  final code = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> join() async {
    final value = normalizeInviteCode(code.text);
    if (!validInviteCode(value)) {
      setState(
        () => error =
            'Enter the complete 20-character code. Dashes and spaces are okay.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final id = await widget.repository.joinGroup(value, widget.userId);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => error = invitationError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('Join a group'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the invitation code shared by the group owner.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: code,
                enabled: !busy,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Invitation code'),
                onSubmitted: busy ? null : (_) => join(),
              ),
              const SizedBox(height: 16),
              const Text(
                'You’ll see the group’s expense history. Existing expenses keep their original participants; joining does not add you to old debts.',
                style: TextStyle(fontSize: 12),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy ? null : join,
          child: Text(busy ? 'Joining…' : 'Join group'),
        ),
      ],
    ),
  );
}

class InviteMembersDialog extends StatefulWidget {
  const InviteMembersDialog({
    super.key,
    required this.group,
    required this.userId,
    required this.repository,
  });
  final SharedGroup group;
  final String userId;
  final InvitationRepository repository;
  @override
  State<InviteMembersDialog> createState() => _InviteMembersDialogState();
}

class _InviteMembersDialogState extends State<InviteMembersDialog> {
  GroupInvitation? invitation;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.repository.activeInvitation(widget.group);
      if (mounted) setState(() => invitation = value);
    } catch (e) {
      if (mounted) setState(() => error = invitationError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change({bool revoke = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (revoke) {
        await widget.repository.revokeInvitation(widget.group.id);
        if (mounted) setState(() => invitation = null);
      } else {
        final value = await widget.repository.createInvitation(
          widget.group.id,
          widget.userId,
        );
        if (mounted) setState(() => invitation = value);
      }
    } catch (e) {
      if (mounted) setState(() => error = invitationError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = invitation;
    final expired =
        current != null && current.expiresAt.isBefore(DateTime.now());
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Invite members'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.group.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Share this code with people you want in your group. They sign in with their own account and choose Join group.',
                ),
                const SizedBox(height: 18),
                if (current != null) ...[
                  SelectableText(
                    displayInviteCode(current.code),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    expired
                        ? 'This code has expired.'
                        : 'Expires ${MaterialLocalizations.of(context).formatMediumDate(current.expiresAt.toLocal())} at ${TimeOfDay.fromDateTime(current.expiresAt.toLocal()).format(context)}',
                  ),
                  TextButton.icon(
                    onPressed: busy || expired
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: displayInviteCode(current.code),
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Invitation code copied'),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy code'),
                  ),
                ] else
                  const Text(
                    'No active code. Create one to invite your friends.',
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Codes last 24 hours and can be used by multiple people, up to 50 group members. Replacing or revoking a code stops future joins; it does not remove existing members.',
                  style: TextStyle(fontSize: 12),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : () => change(),
                  child: Text(
                    current == null ? 'Create invitation' : 'Replace code',
                  ),
                ),
                if (current != null)
                  TextButton(
                    onPressed: busy ? null : () => change(revoke: true),
                    child: const Text('Revoke code'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
