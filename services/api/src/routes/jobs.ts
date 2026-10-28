import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type RouteContext } from '../app.ts';
import { AppError, conflict, notFound } from '../http/errors.ts';
import { optionalText, parseWith, uuidParam } from '../http/validate.ts';
import { STATUSES, allowedTransitions, checkTransition } from '../domain/statuses.ts';
import { MAX_DESCRIPTION_CHARS, MIN_DESCRIPTION_CHARS, cleanDescription, jobsToCsv } from '../domain/jobs.ts';
import { checkEvaluation, evaluationSchema } from '../domain/evaluation.ts';
import {
  addStageEvent,
  applyEvaluation,
  deleteJob,
  findDuplicate,
  getJob,
  insertEvaluation,
  insertJob,
  latestEvaluation,
  listJobs,
  listStageEvents,
  setStatus,
  updateJob,
} from '../repos/jobs.ts';
import { getProfile } from '../repos/profile.ts';
import { currentMasterCv, listStories } from '../repos/content.ts';
import { SHARED_POLICY } from '../ai/prompts/policy.ts';
import { EVALUATION_INSTRUCTIONS, EVALUATION_PROMPT_VERSION } from '../ai/prompts/evaluation.ts';
import { cvBlock, jobBlock, profileBlock, storiesBlock } from '../ai/context.ts';

const listQuery = z.object({
  status: z.enum(STATUSES).optional(),
  saved: z.enum(['true', 'false']).optional(),
  q: z.string().trim().max(100).optional(),
  minScore: z.coerce.number().min(1).max(5).optional(),
  workModel: z.enum(['Remote', 'Hybrid', 'On-site']).optional(),
  sort: z.enum(['recent', 'score', 'company']).default('recent'),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

const workModel = z.enum(['Remote', 'Hybrid', 'On-site']).nullable().optional();

const createJob = z
  .object({
    company: z.string().trim().min(1, 'Add the company.').max(200),
    role: z.string().trim().min(1, 'Add the role title.').max(200),
    description: z
      .string()
      .transform(cleanDescription)
      .pipe(
        z
          .string()
          .min(MIN_DESCRIPTION_CHARS, `Paste at least ${MIN_DESCRIPTION_CHARS} characters of the job description.`)
          .max(MAX_DESCRIPTION_CHARS),
      ),
    location: optionalText(200),
    work_model: workModel,
    salary_text: optionalText(200),
    source_url: z.string().trim().url().max(2000).nullable().optional(),
  })
  .strict();

const patchJob = z
  .object({
    company: z.string().trim().min(1).max(200).optional(),
    role: z.string().trim().min(1).max(200).optional(),
    location: optionalText(200),
    work_model: workModel,
    salary_text: optionalText(200),
    notes: optionalText(10000),
    saved: z.boolean().optional(),
    version: z.number().int().positive().optional(),
  })
  .strict();

const transitionBody = z
  .object({
    to: z.string(),
    note: optionalText(2000),
    feedback: optionalText(10000),
  })
  .strict();

const evaluateBody = z.object({ consent: z.boolean().optional() }).strict();

export function registerJobRoutes(app: FastifyInstance, ctx: RouteContext) {
  app.get('/jobs', async (req) => {
    const auth = requireAuth(req);
    const q = parseWith(listQuery, req.query);
    const rows = await ctx.db.forUser(auth.userId, (tx) =>
      listJobs(tx, auth.userId, {
        status: q.status,
        saved: q.saved === undefined ? undefined : q.saved === 'true',
        q: q.q || undefined,
        minScore: q.minScore,
        workModel: q.workModel,
        sort: q.sort,
        limit: q.limit,
      }),
    );
    return { items: rows };
  });

  app.get('/jobs/export.csv', async (req, reply) => {
    const auth = requireAuth(req);
    const q = parseWith(listQuery, req.query);
    const rows = await ctx.db.forUser(auth.userId, (tx) =>
      listJobs(tx, auth.userId, { status: q.status, q: q.q || undefined, minScore: q.minScore, sort: q.sort, limit: 500 }),
    );
    reply.header('content-type', 'text/csv; charset=utf-8');
    reply.header('content-disposition', 'attachment; filename="career-ops-pipeline.csv"');
    return jobsToCsv(rows);
  });

  app.post('/jobs', async (req, reply) => {
    const auth = requireAuth(req);
    const body = parseWith(createJob, req.body);
    const job = await ctx.db.forUser(auth.userId, async (tx) => {
      const dup = await findDuplicate(tx, auth.userId, body.company, body.role);
      if (dup) throw conflict('duplicate_job', 'You already have this role in your workspace.', { existingId: dup.id });
      return insertJob(tx, auth.userId, body);
    });
    reply.code(201);
    return { ...job, allowedTransitions: allowedTransitions(job.status) };
  });

  app.get('/jobs/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Role');
    return ctx.db.forUser(auth.userId, async (tx) => {
      const job = await getJob(tx, auth.userId, id);
      if (!job) throw notFound('Role');
      const [evaluation, events] = await Promise.all([latestEvaluation(tx, auth.userId, id), listStageEvents(tx, auth.userId, id)]);
      return { job, evaluation, events, allowedTransitions: allowedTransitions(job.status) };
    });
  });

  app.patch('/jobs/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Role');
    const { version, ...patch } = parseWith(patchJob, req.body);
    return ctx.db.forUser(auth.userId, async (tx) => {
      const updated = await updateJob(tx, auth.userId, id, patch, version);
      if (!updated) {
        const exists = await getJob(tx, auth.userId, id);
        if (!exists) throw notFound('Role');
        throw conflict('version_conflict', 'This role changed on another device. Reload and try again.', { current: exists });
      }
      return { ...updated, allowedTransitions: allowedTransitions(updated.status) };
    });
  });

  app.delete('/jobs/:id', async (req, reply) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Role');
    const ok = await ctx.db.forUser(auth.userId, (tx) => deleteJob(tx, auth.userId, id));
    if (!ok) throw notFound('Role');
    return reply.code(204).send();
  });

  app.post('/jobs/:id/transitions', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Role');
    const body = parseWith(transitionBody, req.body);
    return ctx.db.forUser(auth.userId, async (tx) => {
      const job = await getJob(tx, auth.userId, id);
      if (!job) throw notFound('Role');
      const check = checkTransition(job.status, body.to, 'user');
      if (!check.ok) throw new AppError(409, check.code, check.message, { extra: { allowed: allowedTransitions(job.status) } });
      const to = body.to as (typeof STATUSES)[number];
      const updated = await setStatus(tx, auth.userId, id, to);
      await addStageEvent(tx, auth.userId, id, job.status, to, 'user', body.note ?? null, body.feedback ?? null);
      return { ...updated, allowedTransitions: allowedTransitions(updated.status) };
    });
  });

  app.get('/jobs/:id/evaluations/latest', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Role');
    const evaluation = await ctx.db.forUser(auth.userId, (tx) => latestEvaluation(tx, auth.userId, id));
    if (!evaluation) throw notFound('Evaluation');
    return evaluation;
  });

  app.post('/jobs/:id/evaluations', async (req, reply) => {
    const auth = requireAuth(req);
    ctx.limit(req, 'ai', ctx.config.rateLimits.aiPerMinute);
    const id = uuidParam(req.params, 'id', 'Role');
    const body = parseWith(evaluateBody, req.body);

    const input = await ctx.db.forUser(auth.userId, async (tx) => {
      const job = await getJob(tx, auth.userId, id);
      if (!job) throw notFound('Role');
      if (job.status !== 'Inbox' && job.status !== 'Evaluated') {
        throw new AppError(409, 'evaluation_not_allowed', `Roles at ${job.status} stage are not re-evaluated.`);
      }
      const [profile, cv, stories] = await Promise.all([
        getProfile(tx, auth.userId),
        currentMasterCv(tx, auth.userId),
        listStories(tx, auth.userId),
      ]);
      return { job, profile, cv, stories };
    });

    const messages = [
      { role: 'system' as const, content: `${SHARED_POLICY}\n\n${EVALUATION_INSTRUCTIONS}` },
      {
        role: 'user' as const,
        content: [
          profileBlock(input.profile),
          cvBlock(input.cv?.markdown ?? null),
          storiesBlock(input.stories.slice(0, 10)),
          jobBlock(input.job),
        ].join('\n\n'),
      },
    ];

    const result = await ctx.gateway.structured(
      { userId: auth.userId, plan: auth.plan, consent: body.consent },
      'job-evaluation',
      messages,
      { name: 'job_evaluation', schema: evaluationSchema },
      checkEvaluation,
    );
    const e = result.value;

    const saved = await ctx.db.forUser(auth.userId, async (tx) => {
      const job = await getJob(tx, auth.userId, id);
      if (!job) throw notFound('Role');
      const evaluation = await insertEvaluation(tx, auth.userId, id, {
        runId: result.runId,
        score: e.score,
        archetype: e.archetype,
        decision: e.decision,
        result: e,
        promptVersion: EVALUATION_PROMPT_VERSION,
        model: result.model,
      });
      await applyEvaluation(tx, auth.userId, id, {
        score: e.score,
        archetype: e.archetype,
        decision: e.decision,
        legitimacy: e.blocks.g_legitimacy.tier,
        workAuth: e.blocks.a_role_summary.work_auth,
      });
      let status = job.status;
      if (job.status === 'Inbox') {
        await setStatus(tx, auth.userId, id, 'Evaluated');
        await addStageEvent(tx, auth.userId, id, 'Inbox', 'Evaluated', 'system', `Evaluated: ${e.score.toFixed(1)} · ${e.decision}`, null);
        status = 'Evaluated';
      }
      return { evaluation, status };
    });

    reply.code(201);
    return { evaluation: saved.evaluation, status: saved.status, allowedTransitions: allowedTransitions(saved.status) };
  });
}
