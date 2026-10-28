import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGateway, type AiRunRecord, type GatewayStore } from '../../src/ai/gateway.ts';
import { AppError } from '../../src/http/errors.ts';
import { ModelError, type ChatModel, type CompletionRequest } from '../../src/ai/types.ts';
import { checkEvaluation, evaluationSchema } from '../../src/domain/evaluation.ts';
import { sampleEvaluation } from '../../src/ai/dev-model.ts';

function memoryStore(limit = 10) {
  const consents = new Set<string>();
  const usage = new Map<string, number>();
  const runs: AiRunRecord[] = [];
  const store: GatewayStore = {
    async hasConsent(u, f, v) { return consents.has(`${u}|${f}|${v}`); },
    async recordConsent(u, f, v) { consents.add(`${u}|${f}|${v}`); },
    async reserveCredits(u, p, c, l) {
      const k = `${u}|${p}`; const cur = usage.get(k) ?? 0;
      if (cur + c > l) return false; usage.set(k, cur + c); return true;
    },
    async refundCredits(u, p, c) { const k = `${u}|${p}`; usage.set(k, Math.max(0, (usage.get(k) ?? 0) - c)); },
    async recordRun(r) { runs.push(r); return `run-${runs.length}`; },
  };
  return { store, usage, runs, limit };
}

function scriptedModel(outputs: Array<string | Error>): ChatModel & { calls: CompletionRequest[] } {
  const calls: CompletionRequest[] = [];
  return {
    modelName: 'gpt-5-mini',
    calls,
    async complete(req) {
      calls.push(req);
      const next = outputs.shift();
      if (next instanceof Error) throw next;
      return { text: next ?? '', usage: { inputTokens: 100, outputTokens: 50, cachedInputTokens: 0, reasoningTokens: 20 }, finishReason: 'stop', model: 'gpt-5-mini' };
    },
    async *stream() { yield { delta: 'hi' }; },
  };
}

const ctx = { userId: 'u1', plan: 'free' };
const schema = { name: 'job_evaluation', schema: evaluationSchema };

test('requires consent, then remembers it', async () => {
  const m = memoryStore();
  const gw = createGateway({ model: scriptedModel([JSON.stringify(sampleEvaluation()), JSON.stringify(sampleEvaluation())]), store: m.store, creditsForPlan: () => 100 });
  await assert.rejects(gw.structured(ctx, 'job-evaluation', [], schema, checkEvaluation), (e: unknown) => e instanceof AppError && e.code === 'consent_required');
  await gw.structured({ ...ctx, consent: true }, 'job-evaluation', [], schema, checkEvaluation);
  const res = await gw.structured(ctx, 'job-evaluation', [], schema, checkEvaluation);
  assert.equal(res.value.score, 4.2);
});

test('repairs invalid output once, records usage of both attempts', async () => {
  const m = memoryStore();
  const model = scriptedModel(['{"bad":true}', JSON.stringify(sampleEvaluation())]);
  const gw = createGateway({ model, store: m.store, creditsForPlan: () => 100 });
  const res = await gw.structured({ ...ctx, consent: true }, 'job-evaluation', [{ role: 'user', content: 'x' }], schema, checkEvaluation);
  assert.equal(res.runId, 'run-1');
  assert.equal(model.calls.length, 2);
  assert.ok(model.calls[1]!.messages.at(-1)!.content.includes('failed validation'));
  assert.equal(m.runs[0]!.usage.inputTokens, 200);
  assert.equal(m.runs[0]!.status, 'ok');
});

test('fails closed after two bad outputs and refunds credits', async () => {
  const m = memoryStore();
  const gw = createGateway({ model: scriptedModel(['nope', 'still nope']), store: m.store, creditsForPlan: () => 100 });
  await assert.rejects(
    gw.structured({ ...ctx, consent: true }, 'job-evaluation', [], schema, checkEvaluation),
    (e: unknown) => e instanceof AppError && e.code === 'ai_bad_output',
  );
  assert.equal(m.usage.get(`u1|${new Date().toISOString().slice(0, 7)}`), 0);
  assert.equal(m.runs[0]!.status, 'error');
});

test('enforces the monthly quota', async () => {
  const m = memoryStore();
  const gw = createGateway({ model: scriptedModel(['a', 'b', 'c']), store: m.store, creditsForPlan: () => 2 });
  await gw.text({ ...ctx, consent: true }, 'writing-email', []);
  await assert.rejects(gw.text(ctx, 'writing-email', []), (e: unknown) => e instanceof AppError && e.code === 'quota_exceeded' && e.status === 429);
});

test('maps model errors to friendly problems', async () => {
  const m = memoryStore();
  const gw = createGateway({ model: scriptedModel([new ModelError('rate_limited', 'x', true)]), store: m.store, creditsForPlan: () => 100 });
  await assert.rejects(gw.text({ ...ctx, consent: true }, 'assistant', []), (e: unknown) => e instanceof AppError && e.code === 'ai_busy');
});

test('streams deltas and records the run', async () => {
  const m = memoryStore();
  const gw = createGateway({ model: scriptedModel([]), store: m.store, creditsForPlan: () => 100 });
  const run = await gw.prepareStream({ ...ctx, consent: true }, 'assistant');
  const parts: string[] = [];
  const res = await run([], (d) => parts.push(d));
  assert.deepEqual(parts, ['hi']);
  assert.equal(res.text, 'hi');
  assert.equal(m.runs.length, 1);
});
