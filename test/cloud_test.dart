import 'dart:async';

import 'package:app6/cloud/cloud_home.dart';
import 'package:app6/cloud/group_repository.dart';
import 'package:app6/main.dart';
import 'package:app6/main_cloud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGroups implements GroupRepository {
  final controller = StreamController<GroupFeed>.broadcast();
  final created = <String>[];
  bool fail = false;
  @override
  Stream<GroupFeed> watchGroups(String userId) async* {
    yield const GroupFeed([], fromCache: true, pendingWrites: false);
    yield* controller.stream;
  }

  @override
  Future<void> createGroup(String userId, String name) async {
    if (fail) throw StateError('Offline');
    created.add('$userId:$name');
    controller.add(
      GroupFeed(
        [
          SharedGroup(
            id: 'g1',
            name: name,
            ownerId: userId,
            memberIds: [userId],
          ),
        ],
        fromCache: false,
        pendingWrites: false,
      ),
    );
  }
}

void main() {
  test(
    'Group mapping preserves stable membership IDs and prevents mutation',
    () {
      final group = SharedGroup.fromMap('g1', {
        'name': 'Trip',
        'ownerId': 'u1',
        'memberIds': ['u1', 'u2'],
      });
      expect(group.id, 'g1');
      expect(group.memberIds, ['u1', 'u2']);
      expect(() => group.memberIds.add('u3'), throwsUnsupportedError);
    },
  );

  testWidgets(
    'Cloud groups react to live updates and create for the signed-in user',
    (tester) async {
      final repository = FakeGroups();
      addTearDown(repository.controller.close);
      await tester.pumpWidget(
        MyApp(
          home: CloudGroupsPage(
            userId: 'u1',
            repository: repository,
            onSignOut: () async {},
          ),
        ),
      );
      repository.controller.add(
        const GroupFeed([], fromCache: true, pendingWrites: false),
      );
      await tester.pump();
      expect(
        find.text('Showing saved data • cloud not confirmed'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '  Road trip  ');
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(repository.created, ['u1:Road trip']);
      expect(find.text('Road trip'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      repository.controller.add(
        const GroupFeed(
          [
            SharedGroup(
              id: 'g1',
              name: 'Updated elsewhere',
              ownerId: 'u1',
              memberIds: ['u1', 'u2'],
            ),
          ],
          fromCache: false,
          pendingWrites: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Updated elsewhere'), findsOneWidget);
      expect(find.text('2 members'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Failed writes preserve input and allow retry', (tester) async {
    final repository = FakeGroups()..fail = true;
    addTearDown(repository.controller.close);
    await tester.pumpWidget(
      MyApp(
        home: CloudGroupsPage(
          userId: 'u1',
          repository: repository,
          onSignOut: () async {},
        ),
      ),
    );
    repository.controller.add(
      const GroupFeed([], fromCache: false, pendingWrites: false),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Dinner');
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not save this group. Check your connection and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Dinner'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();
    expect(repository.created, ['u1:Dinner']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Unconfigured cloud build shows an actionable message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MyApp(
        home: CloudSetupMessage(
          message: 'Cloud setup is not complete for this build.',
        ),
      ),
    );
    expect(
      find.text('Cloud setup is not complete for this build.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
