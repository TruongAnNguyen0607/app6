import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'group_repository.dart';
import 'expense_repository.dart';
import 'group_details.dart';
import 'invitation_repository.dart';
import 'invitation_widgets.dart';

class CloudAuthGate extends StatelessWidget {
  const CloudAuthGate({
    super.key,
    required this.auth,
    required this.repository,
    required this.expenseRepository,
    this.invitations,
  });
  final FirebaseAuth auth;
  final GroupRepository repository;
  final ExpenseRepository expenseRepository;
  final InvitationRepository? invitations;

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: auth.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Scaffold(
          body: Center(
            child: Text(
              'Unable to restore your sign-in. Please reopen the app.',
            ),
          ),
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = snapshot.data;
      if (user == null) return SignInPage(auth: auth);
      return CloudGroupsPage(
        key: ValueKey(user.uid),
        userId: user.uid,
        repository: repository,
        expenseRepository: expenseRepository,
        invitations: invitations,
        onSignOut: auth.signOut,
      );
    },
  );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.auth});
  final FirebaseAuth auth;
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool register = false, busy = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register) {
        await widget.auth.createUserWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      } else {
        await widget.auth.signInWithEmailAndPassword(
          email: email.text.trim(),
          password: password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(
          () => error = switch (e.code) {
            'operation-not-allowed' => 'Email/password sign-in is not enabled for this app yet. Please contact the app owner.',
            'invalid-email' => 'Enter a valid email address.',
            'network-request-failed' =>
              'Check your internet connection and try again.',
            'weak-password' =>
              'Choose a stronger password with at least 6 characters.',
            'email-already-in-use' =>
              'This email already has an account. Try signing in.',
            'too-many-requests' => 'Too many attempts. Please try again later.',
            _ =>
              register
                  ? 'Could not create your account. Please try again later. (${e.code})'
                  : 'Could not sign in. Check your email and password, or try again later. (${e.code})',
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.spa_rounded,
                      size: 48,
                      color: Color(0xFF206653),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      register
                          ? 'Your shared space starts here.'
                          : 'Welcome to Together.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in to keep your groups with you across devices.',
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: email,
                      enabled: !busy,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) => v == null || !v.contains('@')
                          ? 'Enter your email address'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: password,
                      enabled: !busy,
                      obscureText: true,
                      autofillHints: [
                        register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: const InputDecoration(labelText: 'Password'),
                      validator: (v) => v == null || v.length < 6
                          ? 'Use at least 6 characters'
                          : null,
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
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(
                        busy
                            ? 'Connecting…'
                            : register
                            ? 'Create account'
                            : 'Sign in',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              register = !register;
                              error = null;
                            }),
                      child: Text(
                        register
                            ? 'Already a member? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class CloudGroupsPage extends StatefulWidget {
  const CloudGroupsPage({
    super.key,
    required this.userId,
    required this.repository,
    required this.onSignOut,
    this.expenseRepository,
    this.invitations,
  });
  final String userId;
  final GroupRepository repository;
  final ExpenseRepository? expenseRepository;
  final InvitationRepository? invitations;
  final Future<void> Function() onSignOut;
  @override
  State<CloudGroupsPage> createState() => _CloudGroupsPageState();
}

class _CloudGroupsPageState extends State<CloudGroupsPage> {
  late Stream<GroupFeed> feed;
  final name = TextEditingController();
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    feed = widget.repository.watchGroups(widget.userId);
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> createGroup() async {
    final value = name.text.trim();
    if (value.isEmpty || value.length > 80) {
      setState(() => error = 'Enter a group name with 1–80 characters.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.repository.createGroup(widget.userId, value);
      if (mounted) name.clear();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not save this group. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Together'),
      actions: [
        TextButton(
          onPressed: saving
              ? null
              : () async {
                  try {
                    await widget.onSignOut();
                  } catch (_) {
                    if (mounted) {
                      setState(
                        () => error = 'Unable to sign out. Please try again.',
                      );
                    }
                  }
                },
          child: const Text('Sign out'),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Good things, shared.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your groups, expenses, and balances. All in one place.',
              ),
              const SizedBox(height: 24),
              if (widget.invitations != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: OutlinedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final joinedId = await showDialog<String>(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => JoinGroupDialog(
                                repository: widget.invitations!,
                                userId: widget.userId,
                              ),
                            );
                            if (joinedId != null && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Group joined. It will appear in your groups.',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.group_add_outlined),
                    label: const Text('Join group'),
                  ),
                ),
              TextField(
                controller: name,
                enabled: !saving,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'New group name'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: saving ? null : createGroup,
                icon: const Icon(Icons.add),
                label: Text(
                  saving ? 'Waiting for cloud confirmation…' : 'Create group',
                ),
              ),
              if (saving)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'If you are offline, the change will sync when your connection returns.',
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              StreamBuilder<GroupFeed>(
                key: const ValueKey('cloud-group-feed'),
                stream: feed,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        const Text(
                          'Unable to load groups. Check your connection or try again.',
                        ),
                        TextButton(
                          onPressed: () => setState(
                            () => feed = widget.repository.watchGroups(
                              widget.userId,
                            ),
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        data.pendingWrites
                            ? 'Changes waiting to sync'
                            : data.fromCache
                            ? 'Showing saved data • cloud not confirmed'
                            : 'Up to date',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      if (data.groups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No groups yet. Create your first shared space above.',
                          ),
                        ),
                      for (final group in data.groups)
                        Card(
                          child: ListTile(
                            onTap: widget.expenseRepository == null
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => widget.invitations != null
                                          ? LiveGroupDetails(
                                              group: group,
                                              userId: widget.userId,
                                              expenses:
                                                  widget.expenseRepository!,
                                              invitations: widget.invitations!,
                                            )
                                          : GroupDetailsPage(
                                              group: group,
                                              userId: widget.userId,
                                              repository:
                                                  widget.expenseRepository!,
                                            ),
                                    ),
                                  ),
                            trailing: const Icon(Icons.chevron_right),
                            leading: const Icon(Icons.people_outline),
                            title: Text(group.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${group.memberIds.length} member${group.memberIds.length == 1 ? '' : 's'}',
                                ),
                                if (widget.expenseRepository != null)
                                  GroupSummary(
                                    key: ValueKey(group.id),
                                    groupId: group.id,
                                    userId: widget.userId,
                                    repository: widget.expenseRepository!,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
