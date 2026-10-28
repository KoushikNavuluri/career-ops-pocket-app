/**
 * End-to-end API tests against a real Postgres (pgvector) database.
 * The app connects as a NON-superuser role so row-level security is actually enforced.
 * Skipped when DATABASE_URL is not set.
 */
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import pg from 'pg';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../../src/app.ts';
import { createDb, type Db } from '../../src/db/pool.ts';
import { runMigrations } from '../../src/db/migrate.ts';
import { createVerifier } from '../../src/http/auth.ts';
import { createGateway } from '../../src/ai/gateway.ts';
import { createDevModel } from '../../src/ai/dev-model.ts';
import { createGatewayStore } from '../../src/repos/ai-store.ts';
import type { Config } from '../../src/config.ts';

const ADMIN_URL = process.env.DATABASE_URL;
const ISSUER = 'https://tenant.ciamlogin.example/tenant/v2.0';
const AUDIENCE = '00000000-0000-0000-0000-00000000a11e';
const JD = 'We are hiring a Senior Frontend Engineer to own our design system, accessibility and performance across web and mobile surfaces.';

describe('career api', { skip: !ADMIN_URL }, () => {
  let admin: pg.Pool;
  let db: Db;
  let app: FastifyInstance;
  let privateKey: Awaited<ReturnType<typeof generateKeyPair>>['privateKey'];

  async function token(oid: string, scp = 'access_as_user', aud = AUDIENCE) {
    return new SignJWT({ oid, scp, email: `${oid}@example.com`, name: oid })
      .setProtectedHeader({ alg: 'RS256', kid: 'test' })
      .setIssuer(ISSUER)
      .setAudience(aud)
      .setIssuedAt()
      .setExpirationTime('10m')
      .sign(privateKey);
  }

  async function call(oid: string | null, method: string, url: string, payload?: unknown) {
    const headers: Record<string, string> = {};
    if (oid) headers.authorization = `Bearer ${await token(oid)}`;
    const res = await app.inject({ method: method as 'GET', url, headers, ...(payload !== undefined ? { payload: payload as object } : {}) });
    return { status: res.statusCode, body: res.body ? safeJson(res.body) : null, raw: res.body, headers: res.headers };
  }

  function safeJson(text: string): any {
    try {
      return JSON.parse(text);
    } catch {
      return text;
    }
  }

  before(async () => {
    admin = new pg.Pool({ connectionString: ADMIN_URL });
    await admin.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
    await runMigrations(admin);
    await admin.query(`DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'pocket_app_test') THEN
        CREATE ROLE pocket_app_test LOGIN PASSWORD 'pocket_app_test' NOSUPERUSER NOBYPASSRLS;
      END IF; END $$;`);
    await admin.query('GRANT USAGE ON SCHEMA public TO pocket_app_test');
    await admin.query('GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO pocket_app_test');
    await admin.query('GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO pocket_app_test');

    const appUrl = new URL(ADMIN_URL!);
    appUrl.username = 'pocket_app_test';
    appUrl.password = 'pocket_app_test';
    db = createDb({ connectionString: appUrl.toString(), ssl: false, max: 4 });

    const keys = await generateKeyPair('RS256');
    privateKey = keys.privateKey;
    const jwk = { ...(await exportJWK(keys.publicKey)), kid: 'test', alg: 'RS256' };
    const verifyToken = createVerifier({ keys: createLocalJWKSet({ keys: [jwk] }), issuer: ISSUER, audience: AUDIENCE, requiredScope: 'access_as_user' });

    const config: Config = {
      env: 'test',
      port: 0,
      logLevel: 'silent',
      databaseUrl: appUrl.toString(),
      databaseSsl: false,
      auth: { discoveryUrl: 'unused', audience: AUDIENCE, requiredScope: 'access_as_user' },
      ai: { provider: 'dev', endpoint: '', deployment: 'gpt-5-mini', apiVersion: 'test', timeoutMs: 1000 },
      credits: { free: 150, pro: 1500 },
      rateLimits: { aiPerMinute: 100, writesPerMinute: 1000 },
    };
    const gateway = createGateway({ model: createDevModel(), store: createGatewayStore(db), creditsForPlan: (p) => config.credits[p] ?? 0 });
    app = await buildApp({ config, db, verifyToken, gateway });
    await app.ready();
  });

  after(async () => {
    await app?.close();
    await db?.close();
    await admin?.end();
  });

  test('rejects missing, forged and wrong-scope tokens', async () => {
    assert.equal((await call(null, 'GET', '/v1/me')).status, 401);
    const bad = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: 'Bearer abc.def.ghi' } });
    assert.equal(bad.statusCode, 401);
    const wrongScope = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${await token('x', 'other')}` } });
    assert.equal(wrongScope.statusCode, 401);
    const wrongAud = await app.inject({ method: 'GET', url: '/v1/me', headers: { authorization: `Bearer ${await token('x', 'access_as_user', 'api://other')}` } });
    assert.equal(wrongAud.statusCode, 401);
    assert.equal((await app.inject({ method: 'GET', url: '/healthz' })).statusCode, 200);
  });

  test('first call provisions an empty account; onboarding persists', async () => {
    const me = await call('alice', 'GET', '/v1/me');
    assert.equal(me.status, 200);
    assert.equal(me.body.onboarded, false);
    assert.equal(me.body.usage.limit, 150);
    const patched = await call('alice', 'PATCH', '/v1/profile', { alias: 'Ali', target_role: 'Frontend Engineer', target_market: 'India', onboarded: true });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.target_role, 'Frontend Engineer');
    assert.equal((await call('alice', 'GET', '/v1/me')).body.onboarded, true);
    assert.equal((await call('alice', 'PATCH', '/v1/profile', { target_market: 'Mars' })).status, 400);
    const jobs = await call('alice', 'GET', '/v1/jobs');
    assert.deepEqual(jobs.body.items, []);
  });

  let aliceJobId = '';

  test('job creation validates, dedupes and archives the posting', async () => {
    const short = await call('alice', 'POST', '/v1/jobs', { company: 'Acme', role: 'FE', description: 'too short' });
    assert.equal(short.status, 400);
    assert.ok(short.body.errors.description);
    const created = await call('alice', 'POST', '/v1/jobs', { company: 'Acme Inc.', role: 'Senior Frontend Engineer', description: JD, work_model: 'Remote' });
    assert.equal(created.status, 201);
    assert.equal(created.body.status, 'Inbox');
    assert.deepEqual(created.body.allowedTransitions, ['Applied', 'Discarded', 'SKIP']);
    aliceJobId = created.body.id;
    const dup = await call('alice', 'POST', '/v1/jobs', { company: 'ACME', role: 'senior frontend engineer', description: JD });
    assert.equal(dup.status, 409);
    assert.equal(dup.body.existingId, aliceJobId);
    const detail = await call('alice', 'GET', `/v1/jobs/${aliceJobId}`);
    assert.equal(detail.body.events.length, 1);
  });

  test('another user cannot see or touch the job (API + RLS)', async () => {
    assert.equal((await call('bob', 'GET', `/v1/jobs/${aliceJobId}`)).status, 404);
    assert.equal((await call('bob', 'PATCH', `/v1/jobs/${aliceJobId}`, { saved: true })).status, 404);
    assert.equal((await call('bob', 'DELETE', `/v1/jobs/${aliceJobId}`)).status, 404);
    assert.equal((await call('bob', 'POST', `/v1/jobs/${aliceJobId}/transitions`, { to: 'Applied' })).status, 404);
    assert.equal((await call('bob', 'POST', `/v1/jobs/${aliceJobId}/evaluations`, { consent: true })).status, 404);
    assert.deepEqual((await call('bob', 'GET', '/v1/jobs')).body.items, []);
    // Row-level security: the app role sees nothing without a user context.
    const raw = await db.pool.query('SELECT count(*)::int AS n FROM jobs');
    assert.equal(raw.rows[0].n, 0);
    assert.equal((await call('alice', 'GET', '/v1/jobs/not-a-uuid')).status, 404);
  });

  test('evaluation needs consent, stores a structured report and moves Inbox to Evaluated', async () => {
    const noConsent = await call('alice', 'POST', `/v1/jobs/${aliceJobId}/evaluations`, {});
    assert.equal(noConsent.status, 403);
    assert.equal(noConsent.body.code, 'consent_required');
    const ok = await call('alice', 'POST', `/v1/jobs/${aliceJobId}/evaluations`, { consent: true });
    assert.equal(ok.status, 201, JSON.stringify(ok.body));
    assert.equal(ok.body.status, 'Evaluated');
    assert.equal(ok.body.evaluation.score, 4.2);
    assert.equal(ok.body.evaluation.result.blocks.g_legitimacy.tier, 'Proceed with Caution');
    const detail = await call('alice', 'GET', `/v1/jobs/${aliceJobId}`);
    assert.equal(detail.body.job.score, 4.2);
    assert.equal(detail.body.events.at(-1).actor, 'system');
    const usage = await call('alice', 'GET', '/v1/ai/usage');
    assert.equal(usage.body.used, 3);
  });

  test('server enforces pipeline transitions', async () => {
    const illegal = await call('alice', 'POST', `/v1/jobs/${aliceJobId}/transitions`, { to: 'Hired' });
    assert.equal(illegal.status, 409);
    assert.equal(illegal.body.code, 'transition_not_allowed');
    assert.equal((await call('alice', 'POST', `/v1/jobs/${aliceJobId}/transitions`, { to: 'Evaluated' })).status, 409);
    const applied = await call('alice', 'POST', `/v1/jobs/${aliceJobId}/transitions`, { to: 'Applied', note: 'Submitted on the employer site' });
    assert.equal(applied.status, 200);
    assert.equal(applied.body.status, 'Applied');
    const reeval = await call('alice', 'POST', `/v1/jobs/${aliceJobId}/evaluations`, { consent: true });
    assert.equal(reeval.status, 409);
  });

  test('optimistic concurrency on job edits', async () => {
    const detail = await call('alice', 'GET', `/v1/jobs/${aliceJobId}`);
    const v = detail.body.job.version;
    assert.equal((await call('alice', 'PATCH', `/v1/jobs/${aliceJobId}`, { saved: true, version: v })).status, 200);
    const stale = await call('alice', 'PATCH', `/v1/jobs/${aliceJobId}`, { saved: false, version: v });
    assert.equal(stale.status, 409);
    assert.equal(stale.body.code, 'version_conflict');
  });

  test('master CV is versioned', async () => {
    assert.equal((await call('alice', 'GET', '/v1/cv/master')).body.cv, null);
    await call('alice', 'PUT', '/v1/cv/master', { markdown: '# Alice\n\nFrontend engineer.' });
    await call('alice', 'PUT', '/v1/cv/master', { markdown: '# Alice\n\nSenior frontend engineer.' });
    const versions = await call('alice', 'GET', '/v1/cv/versions');
    assert.equal(versions.body.items.length, 2);
    const restored = await call('alice', 'POST', `/v1/cv/versions/${versions.body.items[1].id}/restore`);
    assert.equal(restored.body.cv.markdown, '# Alice\n\nFrontend engineer.');
    assert.equal((await call('bob', 'GET', `/v1/cv/versions/${versions.body.items[0].id}`)).status, 404);
  });

  test('story bank CRUD with validation', async () => {
    const bad = await call('alice', 'POST', '/v1/stories', { title: 'x', competency: 'Vibes' });
    assert.equal(bad.status, 400);
    const story = { title: 'Rebuilt the design system', competency: 'Ownership', situation: 's', task: 't', action: 'a', result: 'r', reflection: 'f' };
    const created = await call('alice', 'POST', '/v1/stories', story);
    assert.equal(created.status, 201);
    const updated = await call('alice', 'PUT', `/v1/stories/${created.body.id}`, { ...story, result: 'Cut build time by half' });
    assert.equal(updated.body.version, 2);
    assert.equal((await call('bob', 'DELETE', `/v1/stories/${created.body.id}`)).status, 404);
    assert.equal((await call('alice', 'GET', '/v1/stories')).body.items.length, 1);
  });

  test('writing tools validate fields and save drafts as documents', async () => {
    const tools = await call('alice', 'GET', '/v1/ai/tools');
    assert.equal(tools.body.items.length, 10);
    const missing = await call('alice', 'POST', '/v1/ai/drafts/writing-email', { fields: { kind: 'Application' }, consent: true });
    assert.equal(missing.status, 400);
    const draft = await call('alice', 'POST', '/v1/ai/drafts/writing-email', { jobId: aliceJobId, fields: { kind: 'Follow-up' }, consent: true });
    assert.equal(draft.status, 201, JSON.stringify(draft.body));
    assert.ok(draft.body.documentId);
    const docs = await call('alice', 'GET', `/v1/documents?jobId=${aliceJobId}`);
    assert.equal(docs.body.items.length, 1);
    assert.equal((await call('alice', 'POST', '/v1/ai/drafts/writing-nope', {})).status, 404);
    const report = await call('alice', 'POST', `/v1/ai/runs/${draft.body.aiRunId}/report`, { reason: 'Inaccurate claim' });
    assert.equal(report.status, 202);
  });

  test('assistant streams a reply and keeps history', async () => {
    const thread = await call('alice', 'POST', '/v1/assistant/threads', { contextJobId: aliceJobId });
    assert.equal(thread.status, 201);
    const noConsent = await call('alice', 'POST', `/v1/assistant/threads/${thread.body.id}/messages`, { content: 'Hi' });
    assert.equal(noConsent.status, 403);
    const res = await call('alice', 'POST', `/v1/assistant/threads/${thread.body.id}/messages`, { content: 'What should I focus on?', consent: true });
    assert.equal(res.status, 200);
    assert.match(res.headers['content-type'] as string, /text\/event-stream/);
    assert.ok(res.raw.includes('event: delta'));
    assert.ok(res.raw.includes('event: done'));
    const msgs = await call('alice', 'GET', `/v1/assistant/threads/${thread.body.id}/messages`);
    assert.equal(msgs.body.items.length, 2);
    assert.equal(msgs.body.thread.title, 'What should I focus on?');
    assert.equal((await call('bob', 'GET', `/v1/assistant/threads/${thread.body.id}/messages`)).status, 404);
  });

  test('today view and CSV export', async () => {
    const today = await call('alice', 'GET', '/v1/today');
    assert.equal(today.status, 200);
    assert.equal(today.body.counts.pipeline, 1);
    const csv = await call('alice', 'GET', '/v1/jobs/export.csv');
    assert.match(csv.raw, /^Company,Role,Status,Score,Salary,Location,Date\n/);
    assert.ok(csv.raw.includes('Acme Inc.,Senior Frontend Engineer,Applied,4.2'));
  });

  test('export then delete removes every row for the account', async () => {
    const exported = await call('alice', 'GET', '/v1/account/export');
    assert.equal(exported.status, 200);
    assert.equal(exported.body.jobs.length, 1);
    assert.equal((await call('alice', 'DELETE', '/v1/account', { confirm: 'nope' })).status, 400);
    const del = await call('alice', 'DELETE', '/v1/account', { confirm: 'DELETE' });
    assert.equal(del.status, 200);
    assert.equal(del.body.identity, 'not_configured');
    const leftovers = await admin.query(
      `SELECT (SELECT count(*) FROM jobs)::int + (SELECT count(*) FROM stories)::int + (SELECT count(*) FROM cv_versions)::int
        + (SELECT count(*) FROM documents)::int + (SELECT count(*) FROM assistant_messages)::int AS n`,
    );
    assert.equal(leftovers.rows[0].n, 0);
    const fresh = await call('alice', 'GET', '/v1/me');
    assert.equal(fresh.body.onboarded, false);
  });
});
