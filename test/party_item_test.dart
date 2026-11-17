import 'dart:async';

import 'package:app6/cloud/group_repository.dart';
import 'package:app6/cloud/party_item_repository.dart';
import 'package:app6/cloud/party_item_widgets.dart';
import 'package:app6/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePartyItemRepository implements PartyItemRepository {
  final changes = StreamController<PartyItemFeed>.broadcast();
  final items = <PartyItem>[];
  bool fail = false;

  @override
  Stream<PartyItemFeed> watchPartyItems(String partyId) async* {
    if (fail) throw StateError('Connection error');
    yield PartyItemFeed(List.of(items));
    yield* changes.stream;
  }

  @override
  Future<void> addPartyItem(String partyId, PartyItem item) async {
    if (fail) throw StateError('Write failed');
    items.insert(0, item);
    changes.add(PartyItemFeed(List.of(items)));
  }

  @override
  Future<void> assignPartyItem(
      String partyId, String itemId, String? userId) async {
    if (fail) throw StateError('Assignment failed');
    final index = items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      items[index] = items[index].copyWith(
        assignedToUserId: userId,
        clearAssignment: userId == null,
      );
      changes.add(PartyItemFeed(List.of(items)));
    }
  }

  @override
  Future<void> deletePartyItem(String partyId, String itemId) async {
    if (fail) throw StateError('Delete failed');
    items.removeWhere((i) => i.id == itemId);
    changes.add(PartyItemFeed(List.of(items)));
  }
}

const testGroup = SharedGroup(
  id: 'party_1',
  name: 'Summer BBQ Party',
  ownerId: 'user_a',
  memberIds: ['user_a', 'user_b', 'user_c'],
);

void main() {
  group('PartyItem Model & Feed Tests', () {
    test('PartyItem serialization and copyWith work correctly', () {
      final item = PartyItem(
        id: 'i1',
        name: 'Burger Buns',
        category: 'Food & Drink',
        estimatedCents: 1500,
        quantity: 2,
        assignedToUserId: 'user_b',
        notes: 'Gluten free if possible',
        createdBy: 'user_a',
      );

      expect(item.isAssigned, isTrue);
      final map = item.toMap();
      expect(map['name'], 'Burger Buns');
      expect(map['category'], 'Food & Drink');
      expect(map['estimatedCents'], 1500);

      final deserialized = PartyItem.fromMap('i1', map);
      expect(deserialized.name, 'Burger Buns');
      expect(deserialized.quantity, 2);

      final unassigned = item.copyWith(clearAssignment: true);
      expect(unassigned.isAssigned, isFalse);
      expect(unassigned.assignedToUserId, isNull);
    });

    test('PartyItemFeed calculations and filtering', () {
      final items = [
        PartyItem(
          id: '1',
          name: 'Ice',
          category: 'Equipment',
          estimatedCents: 500,
          quantity: 2,
          createdBy: 'user_a',
        ),
        PartyItem(
          id: '2',
          name: 'Soda',
          category: 'Food & Drink',
          estimatedCents: 1000,
          quantity: 1,
          assignedToUserId: 'user_a',
          createdBy: 'user_a',
        ),
        PartyItem(
          id: '3',
          name: 'Chips',
          category: 'Food & Drink',
          estimatedCents: 800,
          quantity: 3,
          assignedToUserId: 'user_b',
          createdBy: 'user_a',
        ),
      ];

      final feed = PartyItemFeed(items);
      expect(feed.totalCount, 3);
      expect(feed.assignedCount, 2);
      expect(feed.unassignedCount, 1);
      // (500*2) + (1000*1) + (800*3) = 1000 + 1000 + 2400 = 4400 cents
      expect(feed.totalEstimatedCents, 4400);

      final foodItems = feed.filterBy(category: 'Food & Drink');
      expect(foodItems.length, 2);

      final myItems = feed.filterBy(
        selectedFilter: 'Mine',
        currentUserId: 'user_a',
      );
      expect(myItems.length, 1);
      expect(myItems.single.name, 'Soda');

      final searchResults = feed.filterBy(searchQuery: 'chips');
      expect(searchResults.length, 1);
      expect(searchResults.single.name, 'Chips');
    });
  });

  group('PartyItemSelectionPage UI Tests', () {
    testWidgets('Renders empty state when party has no items', (tester) async {
      final repo = FakePartyItemRepository();
      addTearDown(repo.changes.close);

      await tester.pumpWidget(
        MyApp(
          home: PartyItemSelectionPage(
            group: testGroup,
            userId: 'user_a',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No party items yet'), findsOneWidget);
      expect(find.text('Create custom item'), findsOneWidget);
      expect(find.text('Browse popular party items'), findsOneWidget);
    });

    testWidgets('Quick adds preset items to party list', (tester) async {
      final repo = FakePartyItemRepository();
      addTearDown(repo.changes.close);

      await tester.pumpWidget(
        MyApp(
          home: PartyItemSelectionPage(
            group: testGroup,
            userId: 'user_a',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open quick catalog
      await tester.ensureVisible(find.text('Browse popular party items'));
      await tester.tap(find.text('Browse popular party items'));
      await tester.pumpAndSettle();

      expect(find.text('Browse Popular Party Essentials'), findsOneWidget);

      // Tap "Drinks & Ice" preset chip
      await tester.ensureVisible(find.textContaining('Drinks & Ice'));
      await tester.tap(find.textContaining('Drinks & Ice'));
      await tester.pumpAndSettle();

      expect(repo.items.length, 1);
      expect(repo.items.first.name, 'Drinks & Ice');
      expect(find.text('Drinks & Ice'), findsWidgets);
    });

    testWidgets('Claims and unclaims party items', (tester) async {
      final repo = FakePartyItemRepository();
      addTearDown(repo.changes.close);

      repo.items.add(
        PartyItem(
          id: 'item_1',
          name: 'Bluetooth Speaker',
          category: 'Entertainment',
          estimatedCents: 0,
          quantity: 1,
          createdBy: 'user_a',
        ),
      );

      await tester.pumpWidget(
        MyApp(
          home: PartyItemSelectionPage(
            group: testGroup,
            userId: 'user_a',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unassigned'), findsWidgets);
      expect(find.text('Claim'), findsOneWidget);

      // Tap Claim
      await tester.ensureVisible(find.text('Claim'));
      await tester.tap(find.text('Claim'));
      await tester.pumpAndSettle();

      expect(repo.items.first.assignedToUserId, 'user_a');
      expect(find.text('Assigned: You'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Assigned'), findsOneWidget);

      // Tap Assigned button to unclaim
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Assigned'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Assigned'));
      await tester.pumpAndSettle();

      expect(repo.items.first.assignedToUserId, isNull);
      expect(find.text('Unassigned'), findsWidgets);
    });

    testWidgets('Adds custom item with validation', (tester) async {
      final repo = FakePartyItemRepository();
      addTearDown(repo.changes.close);

      await tester.pumpWidget(
        MyApp(
          home: PartyItemSelectionPage(
            group: testGroup,
            userId: 'user_a',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap FAB to open add sheet
      await tester.tap(find.text('Add party item'));
      await tester.pumpAndSettle();

      expect(find.text('Add Party Item'), findsOneWidget);

      // Attempt save with empty name
      await tester.tap(find.text('Save item'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an item name'), findsOneWidget);

      // Enter valid fields
      await tester.enterText(
          find.byType(TextFormField).at(0), 'Homemade Lemonade');
      await tester.enterText(find.byType(TextFormField).at(2), '15.50');

      await tester.tap(find.text('Save item'));
      await tester.pumpAndSettle();

      expect(repo.items.length, 1);
      expect(repo.items.first.name, 'Homemade Lemonade');
      expect(repo.items.first.estimatedCents, 1550);
      expect(find.text('Homemade Lemonade'), findsOneWidget);
    });

    testWidgets('Shows error state when repository fails and allows retry',
        (tester) async {
      final repo = FakePartyItemRepository()..fail = true;
      addTearDown(repo.changes.close);

      await tester.pumpWidget(
        MyApp(
          home: PartyItemSelectionPage(
            group: testGroup,
            userId: 'user_a',
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Unable to load party items'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      // Fix failure and tap retry
      repo.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('No party items yet'), findsOneWidget);
    });
  });
}
