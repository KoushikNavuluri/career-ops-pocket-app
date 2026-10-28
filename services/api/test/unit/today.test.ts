import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildToday } from '../../src/domain/today.ts';

const now = new Date('2026-10-28T10:00:00Z');

test('empty workspace suggests CV and first role', () => {
  const t = buildToday([], { hasCv: false, now });
  assert.deepEqual(t.nextMoves.map((m) => m.kind), ['add_cv', 'add_first_role']);
  assert.equal(t.counts.inbox, 0);
});

test('counts, strong matches and follow-ups', () => {
  const t = buildToday(
    [
      { id: '1', company: 'A', role: 'R', status: 'Evaluated', score: 4.6, saved: false, last_event_at: now },
      { id: '2', company: 'B', role: 'R', status: 'Evaluated', score: 3.1, saved: false, last_event_at: now },
      { id: '3', company: 'C', role: 'R', status: 'Applied', score: 4.0, saved: false, last_event_at: '2026-10-10T00:00:00Z' },
      { id: '4', company: 'D', role: 'R', status: 'Inbox', score: null, saved: false, last_event_at: now },
      { id: '5', company: 'E', role: 'R', status: 'Interview', score: 4.1, saved: false, last_event_at: now },
    ],
    { hasCv: true, now },
  );
  assert.equal(t.counts.strongMatches, 1);
  assert.equal(t.counts.pipeline, 2);
  assert.equal(t.counts.interview, 1);
  assert.equal(t.strongMatches[0]?.id, '1');
  const kinds = t.nextMoves.map((m) => m.kind);
  assert.ok(kinds.includes('prepare_application'));
  assert.ok(kinds.includes('follow_up'));
  assert.ok(kinds.includes('prepare_interview'));
  assert.ok(kinds.includes('review_inbox'));
});
