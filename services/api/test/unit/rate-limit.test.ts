import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRateLimiter } from '../../src/http/rate-limit.ts';

test('allows up to the limit then asks to retry', () => {
  let t = 0;
  const rl = createRateLimiter(() => t);
  for (let i = 0; i < 3; i++) assert.equal(rl.hit('u', 3), 0);
  assert.ok(rl.hit('u', 3) > 0);
  t = 61_000;
  assert.equal(rl.hit('u', 3), 0);
  assert.equal(rl.hit('other', 3), 0);
});
