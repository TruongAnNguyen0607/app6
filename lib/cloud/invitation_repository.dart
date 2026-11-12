import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'group_repository.dart';

const inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
String generateInviteCode() {
  final random = Random.secure();
  return List.generate(
    20,
    (_) => inviteAlphabet[random.nextInt(inviteAlphabet.length)],
  ).join();
}

String normalizeInviteCode(String value) =>
    value.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
bool validInviteCode(String value) =>
    RegExp(r'^[A-HJ-NP-Z2-9]{20}$').hasMatch(value);
String displayInviteCode(String code) => [
  for (var i = 0; i < code.length; i += 5)
    code.substring(i, (i + 5).clamp(0, code.length)),
].join('-');

class GroupInvitation {
  const GroupInvitation({
    required this.code,
    required this.groupId,
    required this.expiresAt,
  });
  final String code, groupId;
  final DateTime expiresAt;
}

class InvitationException implements Exception {
  const InvitationException(this.message);
  final String message;
}

abstract class InvitationRepository {
  Stream<SharedGroup?> watchGroup(String groupId);
  Future<GroupInvitation?> activeInvitation(SharedGroup group);
  Future<GroupInvitation> createInvitation(String groupId, String ownerId);
  Future<void> revokeInvitation(String groupId);
  Future<String> joinGroup(String code, String userId);
}

class FirestoreInvitationRepository implements InvitationRepository {
  FirestoreInvitationRepository(this.firestore);
  final FirebaseFirestore firestore;
  @override
  Stream<SharedGroup?> watchGroup(String groupId) => firestore
      .collection('groups')
      .doc(groupId)
      .snapshots()
      .map(
        (doc) => doc.exists ? SharedGroup.fromMap(doc.id, doc.data()!) : null,
      );
  @override
  Future<GroupInvitation?> activeInvitation(SharedGroup group) async {
    final code = group.activeInviteCode;
    if (code == null) return null;
    final doc = await firestore
        .collection('invitations')
        .doc(code)
        .get(const GetOptions(source: Source.server));
    if (!doc.exists) return null;
    return GroupInvitation(
      code: code,
      groupId: group.id,
      expiresAt: (doc.data()!['expiresAt'] as Timestamp).toDate(),
    );
  }

  @override
  Future<GroupInvitation> createInvitation(
    String groupId,
    String ownerId,
  ) async {
    final code = generateInviteCode();
    final expires = DateTime.now().toUtc().add(const Duration(hours: 24));
    // This transaction requires internet. Do not queue a new shareable code offline.
    await firestore.runTransaction((transaction) async {
      final ref = firestore.collection('groups').doc(groupId);
      final group = await transaction.get(ref);
      if (group.data()?['ownerId'] != ownerId) {
        throw const InvitationException(
          'Only the group owner can invite members.',
        );
      }
      transaction.set(firestore.collection('invitations').doc(code), {
        'groupId': groupId,
        'ownerId': ownerId,
        'expiresAt': Timestamp.fromDate(expires),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(ref, {'activeInviteCode': code});
    });
    return GroupInvitation(code: code, groupId: groupId, expiresAt: expires);
  }

  @override
  Future<void> revokeInvitation(String groupId) =>
      firestore.runTransaction((transaction) async {
        final ref = firestore.collection('groups').doc(groupId);
        await transaction.get(ref);
        transaction.update(ref, {'activeInviteCode': null});
      });
  @override
  Future<String> joinGroup(String input, String userId) async {
    final code = normalizeInviteCode(input);
    if (!validInviteCode(code)) {
      throw const InvitationException('Enter the complete invitation code.');
    }
    // Reading only the secret invitation does not expose the group's member list.
    // A transaction makes expiry/revocation and concurrent joins server-checked.
    return firestore.runTransaction((transaction) async {
      final invitation = await transaction.get(
        firestore.collection('invitations').doc(code),
      );
      if (!invitation.exists) {
        throw const InvitationException(
          'This invitation was not found. Ask the owner for a new code.',
        );
      }
      final data = invitation.data()!;
      final groupId = data['groupId'] as String;
      if ((data['expiresAt'] as Timestamp).toDate().isBefore(DateTime.now())) {
        throw const InvitationException(
          'This invitation has expired. Ask the owner for a new code.',
        );
      }
      // arrayUnion keeps retries idempotent and concurrent joins from overwriting members.
      transaction.update(firestore.collection('groups').doc(groupId), {
        'memberIds': FieldValue.arrayUnion([userId]),
        'lastJoinCode': code,
      });
      return groupId;
    });
  }
}

String invitationError(Object error) {
  if (error is InvitationException) return error.message;
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'This code may be revoked, the group may be full, or invitation access is not enabled yet. Ask the owner for a new code.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'Connect to the internet and try again.';
    }
  }
  return 'Could not complete the request. Check your connection and try again.';
}
