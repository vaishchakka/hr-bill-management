import test from 'node:test';
import assert from 'node:assert/strict';
import { createStore } from '../src/store.js';
import { execute, snapshot } from '../src/service.js';
const admin = { id: 'a', role: 'admin' }, member = { id: 'm', role: 'member' };
test('member cannot manage session or see unpresented bills', () => {
  const store = createStore();
  assert.deepEqual(snapshot(store.read(), member).bills, []);
  assert.throws(() => execute(store, member, { type: 'start-session' }), { status: 403 });
  execute(store, admin, { type: 'present-bill', billId: 2 });
  assert.deepEqual(snapshot(store.read(), member).bills.map(b => b.id), [2]);
  execute(store, admin, { type: 'hide-bill' });
  assert.deepEqual(snapshot(store.read(), member).bills, []);
});
test('voting requires presentation and an open ballot; changes do not double count', () => {
  const store = createStore();
  assert.throws(() => execute(store, admin, { type: 'set-status', billId: 1, status: 'Open' }), { status: 409 });
  execute(store, admin, { type: 'present-bill', billId: 1 });
  assert.throws(() => execute(store, member, { type: 'vote', billId: 1, choice: 'Yea' }), { status: 409 });
  execute(store, admin, { type: 'set-status', billId: 1, status: 'Open' });
  execute(store, member, { type: 'vote', billId: 1, choice: 'Yea' });
  execute(store, member, { type: 'vote', billId: 1, choice: 'Nay' });
  assert.deepEqual(store.read().votes['1:1'], { m: 'Nay' });
  assert.deepEqual(snapshot(store.read(), { id: 'other', role: 'member' }).votes, {});
  execute(store, admin, { type: 'end-session' });
  assert.throws(() => execute(store, member, { type: 'vote', billId: 1, choice: 'Yea' }), { status: 409 });
  execute(store, admin, { type: 'present-bill', billId: 1 });
  assert.equal(store.read().bills[0].status, 'Review');
  assert.deepEqual(snapshot(store.read(), member).votes, {});
});
test('invalid commands do not mutate saved state', () => {
  const store = createStore(), before = store.read();
  assert.throws(() => execute(store, admin, { type: 'present-bill', billId: 999 }), { status: 404 });
  assert.throws(() => execute(store, admin, { type: 'set-status', billId: 1, status: 'oops' }), { status: 400 });
  assert.deepEqual(store.read(), before);
});
