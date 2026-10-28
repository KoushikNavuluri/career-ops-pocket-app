import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AppError, badRequest, toProblem } from '../../src/http/errors.ts';

test('AppError becomes problem details', () => {
  const p = toProblem(badRequest('Fix the form.', { company: 'Required.' }));
  assert.equal(p.status, 400);
  assert.equal(p.code, 'validation_failed');
  assert.deepEqual(p.errors, { company: 'Required.' });
});

test('extras are merged and unknown errors are hidden', () => {
  assert.equal(toProblem(new AppError(409, 'duplicate_job', 'x', { extra: { existingId: 'j1' } })).existingId, 'j1');
  const p = toProblem(new Error('db password is hunter2'));
  assert.equal(p.status, 500);
  assert.ok(!JSON.stringify(p).includes('hunter2'));
});

test('framework 4xx errors keep their status', () => {
  assert.equal(toProblem({ statusCode: 413 }).code, 'payload_too_large');
});
