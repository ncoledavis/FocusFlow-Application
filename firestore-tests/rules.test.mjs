// Tests for ../firestore.rules, run against the local Firestore emulator:
//   cd firestore-tests && npm install && npm test

import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment
} from '@firebase/rules-unit-testing';
import {
  Timestamp,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-focusflow',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8')
    }
  });
});

after(async () => {
  await env.cleanup();
});

const now = Timestamp.now();
const INVITE_CODE = 'ABCD2345';

const taskData = (overrides = {}) => ({
  id: 't1',
  ownerUid: 'owner',
  title: 'Write report',
  priority: 'medium',
  scheduleType: 'duration',
  durationMinutes: 25,
  status: 'pending',
  createdBy: 'owner',
  order: 0,
  createdAt: now,
  ...overrides
});

const linkData = (supporterUid, permission, overrides = {}) => ({
  id: `owner_${supporterUid}`,
  ownerUid: 'owner',
  supporterUid,
  ownerEmail: 'owner@example.com',
  supporterEmail: `${supporterUid}@example.com`,
  inviteCode: INVITE_CODE,
  permission,
  status: 'active',
  createdAt: now,
  ...overrides
});

const inviteData = (permission, overrides = {}) => ({
  ownerUid: 'owner',
  ownerEmail: 'owner@example.com',
  permission,
  createdAt: now,
  ...overrides
});

/** Seeds one task for the owner, one for an unrelated user, and three active supporters. */
async function seed() {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'tasks/t1'), taskData());
    await setDoc(doc(db, 'tasks/other1'), taskData({ id: 'other1', ownerUid: 'other', createdBy: 'other' }));
    await setDoc(doc(db, 'links/owner_viewer'), linkData('viewer', 'view'));
    await setDoc(doc(db, 'links/owner_adder'), linkData('adder', 'add'));
    await setDoc(doc(db, 'links/owner_editor'), linkData('editor', 'edit'));
  });
}

async function seedInvite(permission = 'view') {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `invites/${INVITE_CODE}`), inviteData(permission));
  });
}

const as = (uid) => env.authenticatedContext(uid).firestore();
const signedOut = () => env.unauthenticatedContext().firestore();
const ownerTasks = (db) => query(collection(db, 'tasks'), where('ownerUid', '==', 'owner'));

/** What the app does to accept an invite: create the link and consume the invite in one batch. */
async function accept(uid, { permission = 'view', code = INVITE_CODE, link = {}, consume = true } = {}) {
  const db = as(uid);
  const batch = writeBatch(db);
  batch.set(doc(db, `links/owner_${uid}`), linkData(uid, permission, { inviteCode: code, ...link }));
  if (consume) {
    batch.delete(doc(db, `invites/${code}`));
  }
  return batch.commit();
}

beforeEach(async () => {
  await env.clearFirestore();
  await seed();
});

// ---------------------------------------------------------------------------
// Tasks
// ---------------------------------------------------------------------------

describe('tasks: the owner', () => {
  it('can read and list their own tasks', async () => {
    const db = as('owner');
    await assertSucceeds(getDoc(doc(db, 'tasks/t1')));
    await assertSucceeds(getDocs(ownerTasks(db)));
  });

  it('can create a task they author', async () => {
    await assertSucceeds(setDoc(doc(as('owner'), 'tasks/new'), taskData({ id: 'new' })));
  });

  it("cannot create a task in someone else's list", async () => {
    await assertFails(setDoc(doc(as('owner'), 'tasks/new'), taskData({ id: 'new', ownerUid: 'other' })));
  });

  it('cannot create a task authored by someone else', async () => {
    await assertFails(setDoc(doc(as('owner'), 'tasks/new'), taskData({ id: 'new', createdBy: 'other' })));
  });

  it('can change any field of their own task', async () => {
    await assertSucceeds(updateDoc(doc(as('owner'), 'tasks/t1'), { status: 'current', title: 'Renamed' }));
  });

  it('cannot hand a task to another owner', async () => {
    await assertFails(updateDoc(doc(as('owner'), 'tasks/t1'), { ownerUid: 'other' }));
  });

  it('can delete their own task', async () => {
    await assertSucceeds(deleteDoc(doc(as('owner'), 'tasks/t1')));
  });
});

describe('tasks: people with no link', () => {
  it('cannot read or list the owner\'s tasks', async () => {
    const db = as('stranger');
    await assertFails(getDoc(doc(db, 'tasks/t1')));
    await assertFails(getDocs(ownerTasks(db)));
  });

  it('cannot create, change, or delete them', async () => {
    const db = as('stranger');
    await assertFails(setDoc(doc(db, 'tasks/new'), taskData({ id: 'new', createdBy: 'stranger' })));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { priority: 'urgent' }));
    await assertFails(deleteDoc(doc(db, 'tasks/t1')));
  });

  it('are blocked when signed out', async () => {
    await assertFails(getDoc(doc(signedOut(), 'tasks/t1')));
    await assertFails(getDocs(ownerTasks(signedOut())));
  });
});

describe('tasks: a supporter with "view"', () => {
  it('can read and list the owner\'s tasks', async () => {
    const db = as('viewer');
    await assertSucceeds(getDoc(doc(db, 'tasks/t1')));
    await assertSucceeds(getDocs(ownerTasks(db)));
  });

  it('cannot create a task', async () => {
    await assertFails(setDoc(doc(as('viewer'), 'tasks/new'), taskData({ id: 'new', createdBy: 'viewer' })));
  });

  it('cannot change priority or order', async () => {
    await assertFails(updateDoc(doc(as('viewer'), 'tasks/t1'), { priority: 'urgent' }));
    await assertFails(updateDoc(doc(as('viewer'), 'tasks/t1'), { order: 5 }));
  });

  it('cannot delete a task', async () => {
    await assertFails(deleteDoc(doc(as('viewer'), 'tasks/t1')));
  });
});

describe('tasks: a supporter with "add"', () => {
  it('can read and list the owner\'s tasks', async () => {
    const db = as('adder');
    await assertSucceeds(getDoc(doc(db, 'tasks/t1')));
    await assertSucceeds(getDocs(ownerTasks(db)));
  });

  it('can create a pending task they author', async () => {
    await assertSucceeds(
      setDoc(doc(as('adder'), 'tasks/new'), taskData({ id: 'new', createdBy: 'adder' }))
    );
  });

  it('cannot create a task that is already in progress or done', async () => {
    const db = as('adder');
    await assertFails(setDoc(doc(db, 'tasks/a'), taskData({ id: 'a', createdBy: 'adder', status: 'current' })));
    await assertFails(setDoc(doc(db, 'tasks/b'), taskData({ id: 'b', createdBy: 'adder', status: 'done' })));
  });

  it('cannot pass a task off as written by the owner', async () => {
    await assertFails(setDoc(doc(as('adder'), 'tasks/new'), taskData({ id: 'new', createdBy: 'owner' })));
  });

  it('cannot create a task with an invalid priority', async () => {
    await assertFails(
      setDoc(doc(as('adder'), 'tasks/new'), taskData({ id: 'new', createdBy: 'adder', priority: 'bogus' }))
    );
  });

  it('cannot create a task in a list they have no link to', async () => {
    await assertFails(
      setDoc(
        doc(as('adder'), 'tasks/new'),
        taskData({ id: 'new', ownerUid: 'other', createdBy: 'adder' })
      )
    );
  });

  it('cannot change priority or order, or delete', async () => {
    const db = as('adder');
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { priority: 'urgent' }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { order: 5 }));
    await assertFails(deleteDoc(doc(db, 'tasks/t1')));
  });
});

describe('tasks: a supporter with "edit"', () => {
  it('can read and list the owner\'s tasks', async () => {
    const db = as('editor');
    await assertSucceeds(getDoc(doc(db, 'tasks/t1')));
    await assertSucceeds(getDocs(ownerTasks(db)));
  });

  it('can create a pending task they author', async () => {
    await assertSucceeds(
      setDoc(doc(as('editor'), 'tasks/new'), taskData({ id: 'new', createdBy: 'editor' }))
    );
  });

  it('can change priority and order', async () => {
    const db = as('editor');
    await assertSucceeds(updateDoc(doc(db, 'tasks/t1'), { priority: 'urgent' }));
    await assertSucceeds(updateDoc(doc(db, 'tasks/t1'), { order: 3 }));
    await assertSucceeds(updateDoc(doc(db, 'tasks/t1'), { priority: 'low', order: 7 }));
  });

  it('cannot change any other field', async () => {
    const db = as('editor');
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { title: 'Renamed' }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { status: 'done' }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { durationMinutes: 999 }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { ownerUid: 'editor' }));
  });

  it('cannot sneak another field in alongside priority', async () => {
    await assertFails(updateDoc(doc(as('editor'), 'tasks/t1'), { priority: 'urgent', title: 'Renamed' }));
  });

  it('cannot set an invalid priority or a non-integer order', async () => {
    const db = as('editor');
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { priority: 'bogus' }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { order: 1.5 }));
    await assertFails(updateDoc(doc(db, 'tasks/t1'), { order: 'first' }));
  });

  it('cannot delete a task', async () => {
    await assertFails(deleteDoc(doc(as('editor'), 'tasks/t1')));
  });

  it('cannot touch the tasks of someone they have no link to', async () => {
    const db = as('editor');
    await assertFails(getDoc(doc(db, 'tasks/other1')));
    await assertFails(updateDoc(doc(db, 'tasks/other1'), { priority: 'urgent' }));
  });
});

describe('tasks: changes to a link take effect immediately', () => {
  it('a removed supporter loses access', async () => {
    await assertSucceeds(getDoc(doc(as('viewer'), 'tasks/t1')));

    await assertSucceeds(deleteDoc(doc(as('owner'), 'links/owner_viewer')));

    await assertFails(getDoc(doc(as('viewer'), 'tasks/t1')));
    await assertFails(getDocs(ownerTasks(as('viewer'))));
  });

  it('downgrading "edit" to "view" stops edits', async () => {
    await assertSucceeds(updateDoc(doc(as('editor'), 'tasks/t1'), { priority: 'high' }));

    await assertSucceeds(updateDoc(doc(as('owner'), 'links/owner_editor'), { permission: 'view' }));

    await assertFails(updateDoc(doc(as('editor'), 'tasks/t1'), { priority: 'urgent' }));
    await assertSucceeds(getDoc(doc(as('editor'), 'tasks/t1')));
  });

  it('upgrading "view" to "add" allows creating tasks', async () => {
    const task = taskData({ id: 'new', createdBy: 'viewer' });
    await assertFails(setDoc(doc(as('viewer'), 'tasks/new'), task));

    await assertSucceeds(updateDoc(doc(as('owner'), 'links/owner_viewer'), { permission: 'add' }));

    await assertSucceeds(setDoc(doc(as('viewer'), 'tasks/new'), task));
  });
});

// ---------------------------------------------------------------------------
// Invites
// ---------------------------------------------------------------------------

describe('invites: creating and managing', () => {
  it('an owner can create an invite', async () => {
    await assertSucceeds(setDoc(doc(as('owner'), `invites/${INVITE_CODE}`), inviteData('edit')));
  });

  it('cannot create an invite on behalf of someone else', async () => {
    await assertFails(
      setDoc(doc(as('owner'), `invites/${INVITE_CODE}`), inviteData('view', { ownerUid: 'other' }))
    );
  });

  it('cannot create an invite with an unknown permission or a malformed code', async () => {
    await assertFails(setDoc(doc(as('owner'), `invites/${INVITE_CODE}`), inviteData('admin')));
    await assertFails(setDoc(doc(as('owner'), 'invites/SHORT'), inviteData('view')));
  });

  it('another user cannot take over an existing code by creating it again', async () => {
    await seedInvite('view');
    const takeover = inviteData('edit', { ownerUid: 'stranger', ownerEmail: 'stranger@example.com' });
    await assertFails(setDoc(doc(as('stranger'), `invites/${INVITE_CODE}`), takeover));
  });

  it('creating an existing code again counts as an update, which only allows a permission change', async () => {
    await seedInvite('view');
    const later = Timestamp.fromMillis(now.toMillis() + 60_000);
    await assertFails(setDoc(doc(as('owner'), `invites/${INVITE_CODE}`), inviteData('view', { createdAt: later })));
  });

  it('the owner can change a pending invite\'s permission, others cannot', async () => {
    await seedInvite('view');
    await assertFails(updateDoc(doc(as('stranger'), `invites/${INVITE_CODE}`), { permission: 'edit' }));
    await assertSucceeds(updateDoc(doc(as('owner'), `invites/${INVITE_CODE}`), { permission: 'edit' }));
  });

  it('the owner cannot change anything but the permission', async () => {
    await seedInvite('view');
    await assertFails(updateDoc(doc(as('owner'), `invites/${INVITE_CODE}`), { ownerUid: 'other' }));
  });

  it('the owner can cancel an invite, others cannot', async () => {
    await seedInvite('view');
    await assertFails(deleteDoc(doc(as('stranger'), `invites/${INVITE_CODE}`)));
    await assertSucceeds(deleteDoc(doc(as('owner'), `invites/${INVITE_CODE}`)));
  });
});

describe('invites: reading', () => {
  beforeEach(async () => {
    await seedInvite('view');
  });

  it('anyone signed in who knows the code can fetch it', async () => {
    await assertSucceeds(getDoc(doc(as('joiner'), `invites/${INVITE_CODE}`)));
  });

  it('signed-out users cannot fetch it', async () => {
    await assertFails(getDoc(doc(signedOut(), `invites/${INVITE_CODE}`)));
  });

  it('nobody can list other people\'s invites, so codes cannot be harvested', async () => {
    const db = as('stranger');
    await assertFails(getDocs(collection(db, 'invites')));
    await assertFails(getDocs(query(collection(db, 'invites'), where('ownerUid', '==', 'owner'))));
  });

  it('the owner can list their own invites', async () => {
    const db = as('owner');
    await assertSucceeds(getDocs(query(collection(db, 'invites'), where('ownerUid', '==', 'owner'))));
  });
});

// ---------------------------------------------------------------------------
// Accepting an invite
// ---------------------------------------------------------------------------

describe('accepting an invite', () => {
  it('creates the link and consumes the invite', async () => {
    await seedInvite('add');
    await assertSucceeds(accept('joiner', { permission: 'add' }));

    await env.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();
      const link = await getDoc(doc(db, 'links/owner_joiner'));
      const invite = await getDoc(doc(db, `invites/${INVITE_CODE}`));
      assertTrue(link.exists(), 'link should exist');
      assertTrue(!invite.exists(), 'invite should be gone');
    });
  });

  it('gives the new supporter exactly the permission that was invited', async () => {
    await seedInvite('edit');
    await assertSucceeds(accept('joiner', { permission: 'edit' }));

    const db = as('joiner');
    await assertSucceeds(getDoc(doc(db, 'tasks/t1')));
    await assertSucceeds(updateDoc(doc(db, 'tasks/t1'), { priority: 'urgent' }));
    await assertFails(deleteDoc(doc(db, 'tasks/t1')));
  });

  it('works only once: a used code cannot be used again', async () => {
    await seedInvite('view');
    await assertSucceeds(accept('joiner'));
    await assertFails(accept('latecomer'));
  });

  it('is refused if the invite is not consumed in the same batch', async () => {
    await seedInvite('view');
    await assertFails(accept('joiner', { consume: false }));
  });

  it('cannot upgrade the permission beyond what the invite granted', async () => {
    await seedInvite('view');
    await assertFails(accept('joiner', { permission: 'edit' }));
  });

  it('is refused for a code that does not exist', async () => {
    await assertFails(accept('joiner', { code: 'ZZZZ9999' }));
  });

  it('cannot be done on behalf of another user', async () => {
    await seedInvite('view');
    const db = as('joiner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'links/owner_victim'), linkData('victim', 'view'));
    batch.delete(doc(db, `invites/${INVITE_CODE}`));
    await assertFails(batch.commit());
  });

  it('cannot be done by the owner for themselves', async () => {
    await seedInvite('view');
    const db = as('owner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'links/owner_owner'), linkData('owner', 'view'));
    batch.delete(doc(db, `invites/${INVITE_CODE}`));
    await assertFails(batch.commit());
  });

  it('cannot attach a link to a different owner than the invite names', async () => {
    await seedInvite('view');
    const db = as('joiner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'links/other_joiner'), linkData('joiner', 'view', { id: 'other_joiner', ownerUid: 'other' }));
    batch.delete(doc(db, `invites/${INVITE_CODE}`));
    await assertFails(batch.commit());
  });

  it('requires the link ID to match the two UIDs', async () => {
    await seedInvite('view');
    const db = as('joiner');
    const batch = writeBatch(db);
    batch.set(doc(db, 'links/owner_other'), linkData('joiner', 'view', { id: 'owner_other' }));
    batch.delete(doc(db, `invites/${INVITE_CODE}`));
    await assertFails(batch.commit());
  });

  it('a link cannot be created without any invite', async () => {
    await assertFails(setDoc(doc(as('stranger'), 'links/owner_stranger'), linkData('stranger', 'edit')));
  });

  it('a supporter cannot delete an invite without joining', async () => {
    await seedInvite('view');
    await assertFails(deleteDoc(doc(as('joiner'), `invites/${INVITE_CODE}`)));
  });
});

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------

describe('links', () => {
  it('both people can read their link, strangers cannot', async () => {
    await assertSucceeds(getDoc(doc(as('owner'), 'links/owner_viewer')));
    await assertSucceeds(getDoc(doc(as('viewer'), 'links/owner_viewer')));
    await assertFails(getDoc(doc(as('stranger'), 'links/owner_viewer')));
  });

  it('each side can list their own links, and only those', async () => {
    await assertSucceeds(getDocs(query(collection(as('owner'), 'links'), where('ownerUid', '==', 'owner'))));
    await assertSucceeds(getDocs(query(collection(as('viewer'), 'links'), where('supporterUid', '==', 'viewer'))));
    await assertFails(getDocs(query(collection(as('stranger'), 'links'), where('ownerUid', '==', 'owner'))));
    await assertFails(getDocs(collection(as('stranger'), 'links')));
  });

  it('the owner can change the permission', async () => {
    await assertSucceeds(updateDoc(doc(as('owner'), 'links/owner_viewer'), { permission: 'edit' }));
  });

  it('the owner cannot change anything else, or set an unknown permission', async () => {
    const db = as('owner');
    await assertFails(updateDoc(doc(db, 'links/owner_viewer'), { supporterUid: 'someone' }));
    await assertFails(updateDoc(doc(db, 'links/owner_viewer'), { status: 'pending' }));
    await assertFails(updateDoc(doc(db, 'links/owner_viewer'), { permission: 'admin' }));
  });

  it('a supporter cannot raise their own permission', async () => {
    await assertFails(updateDoc(doc(as('viewer'), 'links/owner_viewer'), { permission: 'edit' }));
  });

  it('the owner can remove a supporter, the supporter cannot remove the link', async () => {
    await assertFails(deleteDoc(doc(as('viewer'), 'links/owner_viewer')));
    await assertFails(deleteDoc(doc(as('stranger'), 'links/owner_viewer')));
    await assertSucceeds(deleteDoc(doc(as('owner'), 'links/owner_viewer')));
  });
});

function assertTrue(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
