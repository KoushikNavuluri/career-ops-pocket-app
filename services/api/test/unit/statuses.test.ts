import { test } from 'node:test';
import assert from 'node:assert/strict';
import { allowedTransitions, checkTransition, STATUSES } from '../../src/domain/statuses.ts';

test('every status has a transition entry', () => {
  for (const s of STATUSES) assert.ok(Array.isArray(allowedTransitions(s)));
});

test('users cannot set Evaluated; only the system can', () => {
  assert.equal(checkTransition('Inbox', 'Evaluated', 'user').ok, false);
  assert.equal(checkTransition('Inbox', 'Evaluated', 'system').ok, true);
  assert.equal(checkTransition('Evaluated', 'Evaluated', 'system').ok, true);
});

test('happy path through the funnel', () => {
  const path = ['Inbox', 'Applied', 'Responded', 'Interview', 'Offer', 'Hired'] as const;
  for (let i = 0; i < path.length - 1; i++) {
    assert.deepEqual(checkTransition(path[i]!, path[i + 1]), { ok: true }, `${path[i]} -> ${path[i + 1]}`);
  }
});

test('rejects unknown, same and illegal transitions', () => {
  const unknown = checkTransition('Inbox', 'Nope');
  assert.equal(unknown.ok, false);
  assert.equal(!unknown.ok && unknown.code, 'invalid_status');
  const same = checkTransition('Applied', 'Applied');
  assert.equal(!same.ok && same.code, 'same_status');
  const illegal = checkTransition('Inbox', 'Hired');
  assert.equal(!illegal.ok && illegal.code, 'transition_not_allowed');
  assert.equal(checkTransition('Hired', 'Rejected').ok, false);
});

test('closed roles can be reopened to Inbox', () => {
  for (const s of ['Rejected', 'Discarded', 'SKIP'] as const) assert.equal(checkTransition(s, 'Inbox').ok, true);
});
