import assert from 'node:assert/strict';
import { test } from 'node:test';
import { failures, stage1 } from '../lib/decide.mjs';

const plan = (arm, cost, extra = {}) => ({ arm, complete: 'yes', controllerCost: String(cost), dispatches: '10', inFlight: '0', seatMisses: '0', nudges: '0', sleeps: '0', listAgents: '0', ...extra });
const three = (arm, cost, extras = [{}, {}, {}]) => extras.map(e => plan(arm, cost, e));

test('failures adds launches left running, seat misses, nudges and one busy wait', () => {
  assert.equal(failures({ inFlight: '1', seatMisses: '2', nudges: '1', sleeps: '19', listAgents: '0' }), 4);
  assert.equal(failures({ inFlight: 0, seatMisses: 0, nudges: 0, sleeps: 15, listAgents: 5 }), 1);
  assert.equal(failures({}), 0);
});

test('stage1 waits for three plans per arm', () => {
  assert.equal(stage1([...three('sonnet@high', 2), plan('opus@low', 3)]).decision, 'incomplete');
});

test('stage1 keeps Sonnet when Opus costs too much or fixes nothing', () => {
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 3 }, {}, {}]), ...three('opus@low', 3.1)]).decision, 'keep');
  const even = stage1([...three('sonnet@high', 2, [{ nudges: 1 }, {}, {}]), ...three('opus@low', 2.8, [{ inFlight: 1 }, {}, {}])]);
  assert.equal(even.decision, 'keep');
  assert.ok(Math.abs(even.ratio - 1.4) < 1e-9);
});

test('stage1 switches on a clear margin and is ambiguous on a narrow one', () => {
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 1 }, { inFlight: 1 }, {}]), ...three('opus@low', 2.8)]).decision, 'switch');
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 1 }, {}, {}]), ...three('opus@low', 2.8)]).decision, 'ambiguous');
  assert.equal(stage1([...three('sonnet@high', 2, [{ nudges: 2 }, {}, {}]), ...three('opus@low', 2.8, [{ complete: 'no' }, {}, {}])]).decision, 'ambiguous');
});
