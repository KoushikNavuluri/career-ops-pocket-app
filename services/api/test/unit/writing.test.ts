import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WRITING_FEATURES, WRITING_TOOLS, publicTools, validateToolFields } from '../../src/ai/prompts/writing.ts';
import { FEATURES } from '../../src/ai/features.ts';

test('every writing tool is registered as an AI feature', () => {
  for (const id of WRITING_FEATURES) {
    assert.equal(WRITING_TOOLS[id].id, id);
    assert.ok(FEATURES[id], id);
  }
});

test('public tool list hides prompt text', () => {
  for (const t of publicTools()) assert.equal('instructions' in t, false);
});

test('field validation', () => {
  const tool = WRITING_TOOLS['writing-cover'];
  assert.deepEqual(Object.keys(validateToolFields(tool, {})).sort(), ['problem', 'why']);
  assert.equal(validateToolFields(tool, { why: 'short', problem: 'x'.repeat(20) }).why, 'Add at least 20 characters.');
  assert.equal(validateToolFields(tool, { why: 'x'.repeat(30), problem: 'x'.repeat(20), tone: 'Loud' }).tone, 'Pick one of the options.');
  assert.equal(validateToolFields(tool, { why: 'x'.repeat(30), problem: 'x'.repeat(20), hack: 'y' }).hack, 'Unknown field.');
  assert.deepEqual(validateToolFields(tool, { why: 'x'.repeat(30), problem: 'x'.repeat(20), tone: 'Warm' }), {});
});
