import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type RouteContext } from '../app.ts';
import { AppError, badRequest, notFound } from '../http/errors.ts';
import { parseWith, uuidParam } from '../http/validate.ts';
import { CONSENT_POLICY_VERSION, FEATURES, isAiFeature, usagePeriod } from '../ai/features.ts';
import { SHARED_POLICY } from '../ai/prompts/policy.ts';
import { WRITING_TOOLS, isWritingFeature, publicTools, validateToolFields } from '../ai/prompts/writing.ts';
import { cvBlock, jobBlock, neutralizeTags, profileBlock, storiesBlock } from '../ai/context.ts';
import { getJob } from '../repos/jobs.ts';
import { getProfile } from '../repos/profile.ts';
import { currentMasterCv, insertDocument, listStories } from '../repos/content.ts';

const draftBody = z
  .object({
    jobId: z.string().uuid().nullable().optional(),
    fields: z.record(z.string(), z.unknown()).default({}),
    consent: z.boolean().optional(),
    save: z.boolean().default(true),
  })
  .strict();

const reportBody = z.object({ reason: z.string().trim().min(3).max(1000) }).strict();

export function registerAiRoutes(app: FastifyInstance, ctx: RouteContext) {
  app.get('/ai/tools', async () => ({ items: publicTools(), consentPolicyVersion: CONSENT_POLICY_VERSION }));

  app.get('/ai/usage', async (req) => {
    const auth = requireAuth(req);
    const period = usagePeriod();
    const used = await ctx.db.forUser(auth.userId, async (tx) => {
      const r = await tx.query<{ credits_used: number }>('SELECT credits_used FROM usage_counters WHERE user_id = $1 AND period = $2', [
        auth.userId,
        period,
      ]);
      return r.rows[0]?.credits_used ?? 0;
    });
    return {
      period,
      used,
      limit: ctx.config.credits[auth.plan] ?? ctx.config.credits.free ?? 0,
      model: ctx.config.ai.deployment,
      costs: Object.fromEntries(Object.values(FEATURES).map((f) => [f.id, f.credits])),
    };
  });

  app.get('/consents', async (req) => {
    const auth = requireAuth(req);
    const items = await ctx.db.forUser(auth.userId, async (tx) => {
      const r = await tx.query<{ feature: string; policy_version: string; granted_at: Date }>(
        'SELECT feature, policy_version, granted_at FROM consents WHERE user_id = $1 AND revoked_at IS NULL ORDER BY granted_at DESC',
        [auth.userId],
      );
      return r.rows;
    });
    return { items, currentPolicyVersion: CONSENT_POLICY_VERSION };
  });

  app.delete('/consents/:feature', async (req, reply) => {
    const auth = requireAuth(req);
    const feature = (req.params as { feature?: string }).feature ?? '';
    if (!isAiFeature(feature)) throw notFound('Consent');
    await ctx.db.forUser(auth.userId, (tx) =>
      tx.query('UPDATE consents SET revoked_at = now() WHERE user_id = $1 AND feature = $2 AND revoked_at IS NULL', [auth.userId, feature]),
    );
    return reply.code(204).send();
  });

  app.post('/ai/runs/:id/report', async (req, reply) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'AI response');
    const { reason } = parseWith(reportBody, req.body);
    const ok = await ctx.db.forUser(auth.userId, async (tx) => {
      const r = await tx.query('UPDATE ai_runs SET reported_at = now(), report_reason = $3 WHERE id = $1 AND user_id = $2', [
        id,
        auth.userId,
        reason,
      ]);
      return (r.rowCount ?? 0) > 0;
    });
    if (!ok) throw notFound('AI response');
    req.log.warn({ aiRunId: id }, 'ai output reported by user');
    return reply.code(202).send({ ok: true });
  });

  app.post('/ai/drafts/:feature', async (req, reply) => {
    const auth = requireAuth(req);
    ctx.limit(req, 'ai', ctx.config.rateLimits.aiPerMinute);
    const feature = (req.params as { feature?: string }).feature ?? '';
    if (!isWritingFeature(feature)) throw notFound('Tool');
    const tool = WRITING_TOOLS[feature];
    const body = parseWith(draftBody, req.body);
    const fieldErrors = validateToolFields(tool, body.fields);
    if (Object.keys(fieldErrors).length) throw badRequest('Some fields need attention.', fieldErrors);
    if (tool.needsJob === 'required' && !body.jobId) throw badRequest('Pick the role this is for.', { jobId: 'Required.' });

    const input = await ctx.db.forUser(auth.userId, async (tx) => {
      const job = body.jobId ? await getJob(tx, auth.userId, body.jobId) : null;
      if (body.jobId && !job) throw notFound('Role');
      const [profile, cv, stories] = await Promise.all([
        getProfile(tx, auth.userId),
        currentMasterCv(tx, auth.userId),
        listStories(tx, auth.userId),
      ]);
      return { job, profile, cv, stories };
    });

    const answers = tool.fields
      .map((f) => {
        const v = body.fields[f.key];
        return typeof v === 'string' && v.trim() ? `${f.label}\n<pasted>\n${neutralizeTags(v.trim())}\n</pasted>` : null;
      })
      .filter((x): x is string => x !== null)
      .join('\n\n');

    const messages = [
      { role: 'system' as const, content: `${SHARED_POLICY}\n\nTask: ${tool.instructions}` },
      {
        role: 'user' as const,
        content: [
          profileBlock(input.profile),
          cvBlock(input.cv?.markdown ?? null),
          storiesBlock(input.stories.slice(0, 8)),
          input.job ? jobBlock(input.job) : '<job_posting>No specific role selected.</job_posting>',
          `Candidate input:\n${answers || '(none)'}`,
        ].join('\n\n'),
      },
    ];

    const result = await ctx.gateway.text({ userId: auth.userId, plan: auth.plan, consent: body.consent }, feature, messages);

    let documentId: string | null = null;
    if (body.save) {
      const doc = await ctx.db.forUser(auth.userId, (tx) =>
        insertDocument(tx, auth.userId, {
          jobId: input.job?.id ?? null,
          type: tool.documentType,
          title: input.job ? `${tool.title} · ${input.job.company}` : tool.title,
          body: result.text,
          aiRunId: result.runId,
        }),
      );
      documentId = doc.id;
    }
    if (!result.text) throw new AppError(502, 'ai_bad_output', 'The AI returned an empty draft. Try again.');
    reply.code(201);
    return { text: result.text, documentId, aiRunId: result.runId };
  });
}
