import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app6/main.dart';
import 'package:app6/cloud/invitation_repository.dart';
import 'package:app6/cloud/invitation_widgets.dart';
import 'package:app6/cloud/group_repository.dart';
import 'package:app6/cloud/expense_repository.dart';

const token = 'ABCDEFGHJKLMNPQRSTUV';
const group = SharedGroup(
  id: 'g1',
  name: 'Saturday party',
  ownerId: 'owner',
  memberIds: ['owner'],
);

class FakeInvitations implements InvitationRepository {
  final changes = StreamController<SharedGroup?>.broadcast();
  GroupInvitation? invitation;
  String? joined;
  bool fail = false;
  bool revoked = false;
  @override
  Stream<SharedGroup?> watchGroup(String id) async* {
    yield group;
    yield* changes.stream;
  }

  @override
  Future<GroupInvitation?> activeInvitation(SharedGroup group) async =>
      invitation;
  @override
  Future<GroupInvitation> createInvitation(
    String groupId,
    String ownerId,
  ) async => invitation = GroupInvitation(
    code: token,
    groupId: groupId,
    expiresAt: DateTime.now().add(const Duration(hours: 24)),
  );
  @override
  Future<void> revokeInvitation(String groupId) async {
    revoked = true;
    invitation = null;
  }

  @override
  Future<String> joinGroup(String code, String userId) async {
    if (fail) {
      throw const InvitationException(
        'This invitation has expired. Ask the owner for a new code.',
      );
    }
    joined = '$userId:$code';
    return 'g1';
  }
}

class NoExpenses implements ExpenseRepository {
  @override
  Stream<ExpenseFeed> watchExpenses(String groupId) =>
      Stream.value(const ExpenseFeed([]));
  @override
  Future<void> addExpense(String groupId, SharedExpense expense) async {}
}

void main() {
  test('Secure codes have accepted length, normalize pasted formatting', () {
    for (var i = 0; i < 100; i++) {
      final code = generateInviteCode();
      expect(validInviteCode(code), isTrue);
      expect(normalizeInviteCode(displayInviteCode(code).toLowerCase()), code);
    }
    expect(validInviteCode('SHORT'), isFalse);
    expect(validInviteCode('IIIIIIIIIIIIIIIIIIII'), isFalse);
  });
  testWidgets('Join normalizes code and closes only on success', (
    tester,
  ) async {
    final repo = FakeInvitations();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) =>
                    JoinGroupDialog(repository: repo, userId: 'guest'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'short');
    await tester.tap(find.text('Join group').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('20-character'), findsOneWidget);
    expect(repo.joined, isNull);
    await tester.enterText(
      find.byType(TextField),
      displayInviteCode(token).toLowerCase(),
    );
    await tester.tap(find.text('Join group').last);
    await tester.pumpAndSettle();
    expect(repo.joined, 'guest:$token');
    expect(find.byType(JoinGroupDialog), findsNothing);
  });
  testWidgets('Expired invitation keeps input and displays error', (
    tester,
  ) async {
    final repo = FakeInvitations()..fail = true;
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: Scaffold(
          body: JoinGroupDialog(repository: repo, userId: 'guest'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), token);
    await tester.tap(find.text('Join group').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('has expired'), findsOneWidget);
    expect(find.text(token), findsOneWidget);
  });
  testWidgets('Owner generates and revokes a code at phone size', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final repo = FakeInvitations();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: Scaffold(
          body: InviteMembersDialog(
            group: group,
            userId: 'owner',
            repository: repo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();
    expect(find.text(displayInviteCode(token)), findsOneWidget);
    await tester.ensureVisible(find.text('Revoke code'));
    await tester.tap(find.text('Revoke code'));
    await tester.pumpAndSettle();
    expect(repo.revoked, isTrue);
    expect(
      find.text('No active code. Create one to invite your friends.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Open group receives new members and new expense participant options',
    (tester) async {
      final repo = FakeInvitations();
      addTearDown(repo.changes.close);
      await tester.pumpWidget(
        MyApp(
          home: LiveGroupDetails(
            group: group,
            userId: 'owner',
            expenses: NoExpenses(),
            invitations: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Invite members'), findsOneWidget);
      repo.changes.add(
        const SharedGroup(
          id: 'g1',
          name: 'Saturday party',
          ownerId: 'owner',
          memberIds: ['owner', 'guest'],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Member 2'), findsOneWidget);
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(CheckboxListTile, 'Member 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Non-owner does not see invitation controls', (tester) async {
    final repo = FakeInvitations();
    addTearDown(repo.changes.close);
    await tester.pumpWidget(
      MyApp(
        home: LiveGroupDetails(
          group: group,
          userId: 'guest',
          expenses: NoExpenses(),
          invitations: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Invite members'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
