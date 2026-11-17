import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'expense_repository.dart' show parseCents, dollars;

class PartyItem {
  PartyItem({
    required this.id,
    required this.name,
    required this.category,
    this.estimatedCents = 0,
    this.quantity = 1,
    this.assignedToUserId,
    this.notes,
    required this.createdBy,
  });

  final String id;
  final String name;
  final String category;
  final int estimatedCents;
  final int quantity;
  final String? assignedToUserId;
  final String? notes;
  final String createdBy;

  bool get isAssigned =>
      assignedToUserId != null && assignedToUserId!.trim().isNotEmpty;

  factory PartyItem.fromMap(String id, Map<String, dynamic> map) => PartyItem(
        id: id,
        name: map['name'] as String? ?? '',
        category: map['category'] as String? ?? 'General',
        estimatedCents: (map['estimatedCents'] as num?)?.toInt() ?? 0,
        quantity: (map['quantity'] as num?)?.toInt() ?? 1,
        assignedToUserId: map['assignedToUserId'] as String?,
        notes: map['notes'] as String?,
        createdBy: map['createdBy'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'name': name.trim(),
        'category': category.trim(),
        'estimatedCents': estimatedCents,
        'quantity': quantity,
        'assignedToUserId': assignedToUserId,
        'notes': notes?.trim(),
        'createdBy': createdBy,
      };

  PartyItem copyWith({
    String? id,
    String? name,
    String? category,
    int? estimatedCents,
    int? quantity,
    String? assignedToUserId,
    bool clearAssignment = false,
    String? notes,
    String? createdBy,
  }) {
    return PartyItem(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      estimatedCents: estimatedCents ?? this.estimatedCents,
      quantity: quantity ?? this.quantity,
      assignedToUserId:
          clearAssignment ? null : (assignedToUserId ?? this.assignedToUserId),
      notes: notes ?? this.notes,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}

class PresetPartyItem {
  const PresetPartyItem({
    required this.name,
    required this.category,
    required this.estimatedCents,
    required this.icon,
  });

  final String name;
  final String category;
  final int estimatedCents;
  final IconData icon;
}

const defaultPartyCategories = [
  'All',
  'Food & Drink',
  'Equipment',
  'Decorations',
  'Entertainment',
  'Other',
];

const presetPartyItems = [
  PresetPartyItem(
    name: 'Drinks & Ice',
    category: 'Food & Drink',
    estimatedCents: 2500,
    icon: Icons.local_drink_outlined,
  ),
  PresetPartyItem(
    name: 'Snacks & Appetizers',
    category: 'Food & Drink',
    estimatedCents: 3000,
    icon: Icons.fastfood_outlined,
  ),
  PresetPartyItem(
    name: 'Grill & Main Course',
    category: 'Food & Drink',
    estimatedCents: 5000,
    icon: Icons.outdoor_grill_outlined,
  ),
  PresetPartyItem(
    name: 'Paper Plates & Cups',
    category: 'Equipment',
    estimatedCents: 1500,
    icon: Icons.sanitizer_outlined,
  ),
  PresetPartyItem(
    name: 'Decorations & Balloons',
    category: 'Decorations',
    estimatedCents: 2000,
    icon: Icons.celebration_outlined,
  ),
  PresetPartyItem(
    name: 'Bluetooth Speaker',
    category: 'Entertainment',
    estimatedCents: 0,
    icon: Icons.speaker_outlined,
  ),
  PresetPartyItem(
    name: 'Board & Lawn Games',
    category: 'Entertainment',
    estimatedCents: 0,
    icon: Icons.sports_esports_outlined,
  ),
  PresetPartyItem(
    name: 'Ice Chest & Coolers',
    category: 'Equipment',
    estimatedCents: 0,
    icon: Icons.ac_unit_outlined,
  ),
  PresetPartyItem(
    name: 'Dessert & Cake',
    category: 'Food & Drink',
    estimatedCents: 2500,
    icon: Icons.cake_outlined,
  ),
  PresetPartyItem(
    name: 'Folding Chairs & Table',
    category: 'Equipment',
    estimatedCents: 0,
    icon: Icons.chair_outlined,
  ),
];

class PartyItemFeed {
  const PartyItemFeed(
    this.items, {
    this.fromCache = false,
    this.pendingWrites = false,
  });

  final List<PartyItem> items;
  final bool fromCache;
  final bool pendingWrites;

  int get totalCount => items.length;
  int get assignedCount => items.where((i) => i.isAssigned).length;
  int get unassignedCount => items.where((i) => !i.isAssigned).length;
  int get totalEstimatedCents =>
      items.fold(0, (sum, i) => sum + (i.estimatedCents * i.quantity));

  List<PartyItem> filterBy({
    String category = 'All',
    String? selectedFilter, // 'All', 'Unassigned', 'Assigned', 'Mine'
    String? currentUserId,
    String searchQuery = '',
  }) {
    return items.where((item) {
      if (category != 'All' && item.category != category) {
        return false;
      }
      if (selectedFilter == 'Unassigned' && item.isAssigned) {
        return false;
      }
      if (selectedFilter == 'Assigned' && !item.isAssigned) {
        return false;
      }
      if (selectedFilter == 'Mine' &&
          (currentUserId == null || item.assignedToUserId != currentUserId)) {
        return false;
      }
      if (searchQuery.isNotEmpty) {
        final query = searchQuery.toLowerCase();
        final matchName = item.name.toLowerCase().contains(query);
        final matchCategory = item.category.toLowerCase().contains(query);
        final matchNotes = (item.notes ?? '').toLowerCase().contains(query);
        if (!matchName && !matchCategory && !matchNotes) {
          return false;
        }
      }
      return true;
    }).toList();
  }
}

abstract class PartyItemRepository {
  Stream<PartyItemFeed> watchPartyItems(String partyId);
  Future<void> addPartyItem(String partyId, PartyItem item);
  Future<void> assignPartyItem(String partyId, String itemId, String? userId);
  Future<void> deletePartyItem(String partyId, String itemId);
}

class FirestorePartyItemRepository implements PartyItemRepository {
  FirestorePartyItemRepository(this.firestore);
  final FirebaseFirestore firestore;

  @override
  Stream<PartyItemFeed> watchPartyItems(String partyId) => firestore
      .collection('groups')
      .doc(partyId)
      .collection('party_items')
      .snapshots(includeMetadataChanges: true)
      .map(
        (snapshot) => PartyItemFeed(
          snapshot.docs
              .map((doc) => PartyItem.fromMap(doc.id, doc.data()))
              .toList(),
          fromCache: snapshot.metadata.isFromCache,
          pendingWrites: snapshot.metadata.hasPendingWrites,
        ),
      );

  @override
  Future<void> addPartyItem(String partyId, PartyItem item) {
    if (item.name.trim().isEmpty || item.name.length > 80) {
      throw ArgumentError('Item name must be between 1 and 80 characters.');
    }
    if (item.quantity < 1 || item.quantity > 100) {
      throw ArgumentError('Quantity must be between 1 and 100.');
    }
    if (item.estimatedCents < 0 || item.estimatedCents > 100000000) {
      throw ArgumentError('Estimated cost must be valid.');
    }
    return firestore
        .collection('groups')
        .doc(partyId)
        .collection('party_items')
        .doc(item.id)
        .set({
      ...item.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> assignPartyItem(String partyId, String itemId, String? userId) {
    return firestore
        .collection('groups')
        .doc(partyId)
        .collection('party_items')
        .doc(itemId)
        .update({
      'assignedToUserId': userId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deletePartyItem(String partyId, String itemId) {
    return firestore
        .collection('groups')
        .doc(partyId)
        .collection('party_items')
        .doc(itemId)
        .delete();
  }
}
