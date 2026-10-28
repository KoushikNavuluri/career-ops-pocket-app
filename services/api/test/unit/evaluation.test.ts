import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkEvaluation, evaluationSchema } from '../../src/domain/evaluation.ts';
import { validate, parseJsonLoose, type Schema } from '../../src/domain/json-schema.ts';
import { sampleEvaluation } from '../../src/ai/dev-model.ts';

test('sample evaluation satisfies the strict schema', () => {
  assert.deepEqual(validate(evaluationSchema, sampleEvaluation()), { ok: true });
});

test('strict schema: every object lists all properties as required and forbids extras', () => {
  const walk = (s: Schema) => {
    if (s.type === 'object') {
      assert.deepEqual([...s.required].sort(), Object.keys(s.properties).sort());
      assert.equal(s.additionalProperties, false);
      Object.values(s.properties).forEach(walk);
    } else if (s.type === 'array') walk(s.items);
  };
  walk(evaluationSchema);
});

test('rejects out-of-range scores and bad enums', () => {
  assert.equal(checkEvaluation({ ...sampleEvaluation(), score: 7 }).ok, false);
  assert.equal(checkEvaluation({ ...sampleEvaluation(), decision: 'Maybe' }).ok, false);
  assert.equal(checkEvaluation({ ...sampleEvaluation(), extra: 1 }).ok, false);
});

test('rounds score and drops H block below 4.5', () => {
  const raw = sampleEvaluation(4.26);
  raw.blocks.h_application_answers = [{ question: 'q', draft: 'd' }] as never;
  const res = checkEvaluation(raw);
  assert.ok(res.ok);
  if (res.ok) {
    assert.equal(res.value.score, 4.3);
    assert.deepEqual(res.value.blocks.h_application_answers, []);
  }
});

test('inferred requirements are never critical/high', () => {
  const raw = sampleEvaluation();
  raw.blocks.b_cv_match.requirements[0]!.evidence_tier = 'inferred';
  const res = checkEvaluation(raw);
  assert.ok(res.ok && res.value.blocks.b_cv_match.requirements[0]!.importance === 'meaningful');
});

test('parseJsonLoose handles fences and garbage', () => {
  assert.deepEqual(parseJsonLoose('```json\n{"a":1}\n```'), { a: 1 });
  assert.equal(parseJsonLoose('not json'), undefined);
});
