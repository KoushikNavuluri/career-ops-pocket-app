import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type RouteContext } from '../app.ts';
import { notFound, toProblem } from '../http/errors.ts';
import { parseWith, uuidParam } from '../http/validate.ts';
import { SHARED_POLICY } from '../ai/prompts/policy.ts';
import { ASSISTANT_INSTRUCTIONS } from '../ai/prompts/assistant.ts';
import { cvBlock, jobBlock, pipelineBlock, profileBlock, trimHistory, truncate } from '../ai/context.ts';
import type { ChatMessage } from '../ai/types.ts';
import { addMessage, createThread, deleteThread, getThread, listMessages, listThreads, updateThread } from '../repos/assistant.ts';
import { getJob, latestEvaluation, listJobs } from '../repos/jobs.ts';
import { getProfile } from '../repos/profile.ts';
import { currentMasterCv } from '../repos/content.ts';
import type { Evaluation } from '../domain/evaluation.ts';

const createBody = z.object({ contextJobId: z.string().uuid().nullable().optional() }).strict();
const patchBody = z
  .object({ title: z.string().trim().min(1).max(120).optional(), contextJobId: z.string().uuid().nullable().optional() })
  .strict();
const messageBody = z
  .object({
    content: z.string().trim().min(1, 'Write a message.').max(8000, 'Keep messages under 8,000 characters.'),
    contextJobId: z.string().uuid().nullable().optional(),
    consent: z.boolean().optional(),
  })
  .strict();

function evaluationSummary(result: unknown): string {
  const e = result as Partial<Evaluation> | null;
  if (!e || typeof e !== 'object') return '';
  const parts = [
    e.verdict ? `Verdict: ${e.verdict}` : '',
    e.top_strengths?.length ? `Strengths: ${e.top_strengths.join('; ')}` : '',
    e.soft_gaps?.length ? `Gaps: ${e.soft_gaps.join('; ')}` : '',
    e.hard_stops?.length ? `Hard stops: ${e.hard_stops.join('; ')}` : '',
    e.next_action ? `Suggested next action: ${e.next_action}` : '',
  ].filter(Boolean);
  return truncate(parts.join('\n'), 3000);
}

export function registerAssistantRoutes(app: FastifyInstance, ctx: RouteContext) {
  app.get('/assistant/threads', async (req) => {
    const auth = requireAuth(req);
    const items = await ctx.db.forUser(auth.userId, (tx) => listThreads(tx, auth.userId));
    return { items };
  });

  app.post('/assistant/threads', async (req, reply) => {
    const auth = requireAuth(req);
    const body = parseWith(createBody, req.body);
    const thread = await ctx.db.forUser(auth.userId, async (tx) => {
      if (body.contextJobId && !(await getJob(tx, auth.userId, body.contextJobId))) throw notFound('Role');
      return createThread(tx, auth.userId, body.contextJobId ?? null);
    });
    reply.code(201);
    return thread;
  });

  app.patch('/assistant/threads/:id', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Conversation');
    const body = parseWith(patchBody, req.body);
    return ctx.db.forUser(auth.userId, async (tx) => {
      if (!(await getThread(tx, auth.userId, id))) throw notFound('Conversation');
      if (body.contextJobId && !(await getJob(tx, auth.userId, body.contextJobId))) throw notFound('Role');
      await updateThread(tx, auth.userId, id, { title: body.title, contextJobId: body.contextJobId });
      return getThread(tx, auth.userId, id);
    });
  });

  app.delete('/assistant/threads/:id', async (req, reply) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Conversation');
    const ok = await ctx.db.forUser(auth.userId, (tx) => deleteThread(tx, auth.userId, id));
    if (!ok) throw notFound('Conversation');
    return reply.code(204).send();
  });

  app.get('/assistant/threads/:id/messages', async (req) => {
    const auth = requireAuth(req);
    const id = uuidParam(req.params, 'id', 'Conversation');
    return ctx.db.forUser(auth.userId, async (tx) => {
      const thread = await getThread(tx, auth.userId, id);
      if (!thread) throw notFound('Conversation');
      return { thread, items: await listMessages(tx, auth.userId, id) };
    });
  });

  /**
   * Send a message and stream the reply as Server-Sent Events:
   *   event: delta  data: {"text": "..."}
   *   event: done   data: {"messageId": "...", "userMessageId": "...", "aiRunId": "..."}
   *   event: error  data: <problem details>
   * Consent, quota and validation failures are returned as normal HTTP problems before streaming.
   */
  app.post('/assistant/threads/:id/messages', async (req, reply) => {
    const auth = requireAuth(req);
    ctx.limit(req, 'ai', ctx.config.rateLimits.aiPerMinute);
    const id = uuidParam(req.params, 'id', 'Conversation');
    const body = parseWith(messageBody, req.body);

    const prepared = await ctx.db.forUser(auth.userId, async (tx) => {
      const thread = await getThread(tx, auth.userId, id);
      if (!thread) throw notFound('Conversation');
      const contextJobId = body.contextJobId !== undefined ? body.contextJobId : thread.context_job_id;
      const [history, profile, cv, jobs, job] = await Promise.all([
        listMessages(tx, auth.userId, id, 40),
        getProfile(tx, auth.userId),
        currentMasterCv(tx, auth.userId),
        listJobs(tx, auth.userId, { sort: 'recent', limit: 100 }),
        contextJobId ? getJob(tx, auth.userId, contextJobId) : Promise.resolve(null),
      ]);
      if (contextJobId && !job) throw notFound('Role');
      const evaluation = job ? await latestEvaluation(tx, auth.userId, job.id) : null;
      return { thread, contextJobId, history, profile, cv, jobs, job, evaluation };
    });

    const run = await ctx.gateway.prepareStream({ userId: auth.userId, plan: auth.plan, consent: body.consent }, 'assistant');

    const userMessage = await ctx.db.forUser(auth.userId, async (tx) => {
      const m = await addMessage(tx, auth.userId, id, 'user', body.content, null);
      const updates: { title?: string; contextJobId?: string | null } = {};
      if (prepared.thread.title === 'New conversation') updates.title = body.content.slice(0, 48);
      if (prepared.contextJobId !== prepared.thread.context_job_id) updates.contextJobId = prepared.contextJobId;
      if (updates.title !== undefined || updates.contextJobId !== undefined) await updateThread(tx, auth.userId, id, updates);
      return m;
    });

    const contextParts = [
      profileBlock(prepared.profile),
      pipelineBlock(prepared.jobs),
      cvBlock(prepared.cv ? truncate(prepared.cv.markdown, 6000) : null),
    ];
    if (prepared.job) {
      contextParts.push(`Selected role:\n${jobBlock({ ...prepared.job, description: truncate(prepared.job.description, 8000) })}`);
      const summary = prepared.evaluation ? evaluationSummary(prepared.evaluation.result) : '';
      if (summary) contextParts.push(`Latest evaluation of the selected role (score ${prepared.evaluation?.score}):\n${summary}`);
    }

    const messages: ChatMessage[] = [
      { role: 'system', content: `${SHARED_POLICY}\n\n${ASSISTANT_INSTRUCTIONS}\n\nWorkspace context:\n${contextParts.join('\n\n')}` },
      ...trimHistory(prepared.history).map((m) => ({ role: m.role, content: m.content })),
      { role: 'user', content: body.content },
    ];

    reply.hijack();
    const raw = reply.raw;
    raw.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    });
    const send = (event: string, data: unknown) => {
      if (!raw.writableEnded) raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };
    const abort = new AbortController();
    raw.on('close', () => {
      if (!raw.writableEnded) abort.abort();
    });
    const keepAlive = setInterval(() => {
      if (!raw.writableEnded) raw.write(': keep-alive\n\n');
    }, 15_000);

    try {
      const result = await run(messages, (text) => send('delta', { text }), abort.signal);
      const saved = await ctx.db.forUser(auth.userId, (tx) => addMessage(tx, auth.userId, id, 'assistant', result.text, result.runId));
      send('done', { messageId: saved.id, userMessageId: userMessage.id, aiRunId: result.runId });
    } catch (err) {
      req.log.warn({ code: toProblem(err).code }, 'assistant stream failed');
      send('error', toProblem(err));
    } finally {
      clearInterval(keepAlive);
      raw.end();
    }
  });
}
