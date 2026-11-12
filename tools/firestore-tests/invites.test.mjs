import {readFileSync} from 'node:fs';
import {before, after, beforeEach, test} from 'node:test';
import assert from 'node:assert/strict';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, updateDoc, collection, getDocs, writeBatch, arrayUnion, Timestamp, serverTimestamp, runTransaction} from 'firebase/firestore';
let env;
const code = 'ABCDEFGHJKLMNPQRSTUV';
const second = '23456789ABCDEFGHJKLM';
const db = uid => env.authenticatedContext(uid).firestore();
const groupRef = (database, id = 'g1') => doc(database, 'groups', id);
async function issue(database, token = code, group = 'g1', owner = 'owner') {
  const batch = writeBatch(database);
  batch.set(doc(database, 'invitations', token), {groupId: group, ownerId: owner, expiresAt: Timestamp.fromMillis(Date.now() + 86400000), createdAt: serverTimestamp()});
  batch.update(groupRef(database, group), {activeInviteCode: token});
  return batch.commit();
}
const join = (database, uid, token = code, group = 'g1', extra = {}) => updateDoc(groupRef(database, group), {memberIds: arrayUnion(uid), lastJoinCode: token, ...extra});
before(async () => {
  env = await initializeTestEnvironment({projectId: 'demo-together-invites', firestore: {rules: readFileSync('../../firestore.rules', 'utf8')}});
});
after(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    for (const id of ['g1', 'g2']) await setDoc(groupRef(context.firestore(), id), {name: id, ownerId: 'owner', memberIds: ['owner'], createdAt: Timestamp.now()});
  });
});
test('owner issues code; signed-in guest joins and repeat join is idempotent', async () => {
  await assertSucceeds(issue(db('owner')));
  await assertFails(getDoc(groupRef(db('guest'))));
  await assertSucceeds(getDoc(doc(db('guest'), 'invitations', code)));
  await assertSucceeds(join(db('guest'), 'guest'));
  await assertSucceeds(join(db('guest'), 'guest'));
  const record = await assertSucceeds(getDoc(groupRef(db('guest'))));
  assert.deepEqual(record.data().memberIds, ['owner', 'guest']);
});
test('no unauthenticated reads, listing codes, or direct membership changes', async () => {
  await issue(db('owner'));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'invitations', code)));
  await assertFails(getDocs(collection(db('guest'), 'invitations')));
  await assertFails(updateDoc(groupRef(db('guest')), {memberIds: ['owner', 'guest']}));
  await assertFails(join(anon, 'guest'));
});
test('non-owner cannot issue, rotate, revoke or modify invitation records', async () => {
  await assertFails(issue(db('guest')));
  await issue(db('owner'));
  await join(db('guest'), 'guest');
  await assertFails(issue(db('guest'), second, 'g1', 'guest'));
  await assertFails(updateDoc(groupRef(db('guest')), {activeInviteCode: null}));
  await assertFails(updateDoc(doc(db('owner'), 'invitations', code), {expiresAt: Timestamp.fromMillis(Date.now() + 90000000)}));
});
test('code cannot target another group or add someone else or change ownership', async () => {
  await issue(db('owner'));
  await assertFails(join(db('guest'), 'guest', code, 'g2'));
  await assertFails(join(db('guest'), 'victim'));
  await assertFails(join(db('guest'), 'guest', code, 'g1', {ownerId: 'guest'}));
  await assertFails(join(db('guest'), 'guest', code, 'g1', {name: 'stolen'}));
  await assertFails(join(db('guest'), 'guest', code, 'g1', {memberIds: ['guest']}));
  await assertFails(join(db('guest'), 'guest', code, 'g1', {memberIds: ['owner', 'guest', 'other']}));
});
test('expired, replaced, revoked and unknown invitations fail', async () => {
  await issue(db('owner'));
  await env.withSecurityRulesDisabled(context => updateDoc(doc(context.firestore(), 'invitations', code), {expiresAt: Timestamp.fromMillis(Date.now() - 1000)}));
  await assertFails(join(db('guest'), 'guest'));
  await issue(db('owner'), second);
  await assertFails(join(db('guest'), 'guest'));
  await assertSucceeds(updateDoc(groupRef(db('owner')), {activeInviteCode: null}));
  await assertFails(join(db('guest'), 'guest', second));
  await assertFails(join(db('guest'), 'guest', 'ZZZZZZZZZZZZZZZZZZZZ'));
});
test('concurrent joins retain both members and full groups reject new members', async () => {
  await issue(db('owner'));
  await Promise.all([assertSucceeds(join(db('one'), 'one')), assertSucceeds(join(db('two'), 'two'))]);
  assert.deepEqual(new Set((await getDoc(groupRef(db('owner')))).data().memberIds), new Set(['owner', 'one', 'two']));
  await env.withSecurityRulesDisabled(context => updateDoc(groupRef(context.firestore()), {memberIds: ['owner', ...Array.from({length:49}, (_,i) => `member${i}`)]}));
  await assertFails(join(db('guest'), 'guest'));
});
test('new member sees old expenses without being added to old splits', async () => {
  await issue(db('owner'));
  const expense = doc(db('owner'), 'groups/g1/expenses/e1');
  await assertSucceeds(setDoc(expense, {title:'Dinner', amountCents:1001, payerId:'owner', participantIds:['owner'], createdBy:'owner', createdAt:serverTimestamp()}));
  await assertFails(getDoc(doc(db('guest'), 'groups/g1/expenses/e1')));
  await join(db('guest'), 'guest');
  const old = await assertSucceeds(getDoc(doc(db('guest'), 'groups/g1/expenses/e1')));
  assert.deepEqual(old.data().participantIds, ['owner']);
  await assertFails(updateDoc(doc(db('guest'), 'groups/g1/expenses/e1'), {participantIds:['owner','guest']}));
  await assertSucceeds(setDoc(doc(db('guest'), 'groups/g1/expenses/e2'), {title:'Lunch', amountCents:2000, payerId:'guest', participantIds:['owner','guest'], createdBy:'guest', createdAt:serverTimestamp()}));
});


test('client join transaction reads only the invitation before membership update', async () => {
  await issue(db('owner'));
  const guest = db('guest');
  await assertSucceeds(runTransaction(guest, async transaction => {
    const invite = await transaction.get(doc(guest, 'invitations', code));
    transaction.update(groupRef(guest, invite.data().groupId), {memberIds: arrayUnion('guest'), lastJoinCode: code});
  }));
  await assertSucceeds(getDoc(groupRef(guest)));
});
test('owner cannot create malformed or excessively long-lived codes', async () => {
  for (const hours of [-1, 26]) {
    const owner = db('owner');
    const batch = writeBatch(owner);
    batch.set(doc(owner, 'invitations', code), {groupId: 'g1', ownerId: 'owner', expiresAt: Timestamp.fromMillis(Date.now() + hours * 3600000), createdAt: serverTimestamp()});
    batch.update(groupRef(owner), {activeInviteCode: code});
    await assertFails(batch.commit());
  }
  await assertFails(issue(db('owner'), 'SHORT'));
});
