import 'package:cloud_firestore/cloud_firestore.dart';

/// Cloud records use stable IDs rather than display names for ownership.
class SharedGroup {
  const SharedGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.memberIds,
    this.activeInviteCode,
  });
  final String id;
  final String name;
  final String ownerId;
  final List<String> memberIds;
  final String? activeInviteCode;

  factory SharedGroup.fromMap(String id, Map<String, dynamic> data) =>
      SharedGroup(
        id: id,
        name: data['name'] as String,
        ownerId: data['ownerId'] as String,
        activeInviteCode: data['activeInviteCode'] as String?,
        memberIds: List<String>.unmodifiable(
          (data['memberIds'] as List).cast<String>(),
        ),
      );
}

class GroupFeed {
  const GroupFeed(
    this.groups, {
    required this.fromCache,
    required this.pendingWrites,
  });
  final List<SharedGroup> groups;
  final bool fromCache;
  final bool pendingWrites;
}

abstract class GroupRepository {
  Stream<GroupFeed> watchGroups(String userId);
  Future<void> createGroup(String userId, String name);
}

class FirestoreGroupRepository implements GroupRepository {
  FirestoreGroupRepository(this.firestore);
  final FirebaseFirestore firestore;

  @override
  Stream<GroupFeed> watchGroups(String userId) => firestore
      .collection('groups')
      .where('memberIds', arrayContains: userId)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        final groups =
            snapshot.docs
                .map((doc) => SharedGroup.fromMap(doc.id, doc.data()))
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );
        return GroupFeed(
          groups,
          fromCache: snapshot.metadata.isFromCache,
          pendingWrites: snapshot.metadata.hasPendingWrites,
        );
      });

  @override
  Future<void> createGroup(String userId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError('Group names must contain 1–80 characters.');
    }
    // New groups start with only their owner; invitations add other accounts.
    return firestore.collection('groups').doc().set({
      'name': trimmed,
      'ownerId': userId,
      'memberIds': [userId],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
