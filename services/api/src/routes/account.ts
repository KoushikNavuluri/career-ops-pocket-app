import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { actorHash, requireAuth, type RouteContext } from '../app.ts';
import { parseWith } from '../http/validate.ts';
import { audit, deleteUser } from '../repos/users.ts';

const deleteBody = z.object({ confirm: z.literal('DELETE', { errorMap: () => ({ message: 'Type DELETE to confirm.' }) }) }).strict();

const EXPORT_TABLES = [
  ['profile', 'SELECT * FROM profiles WHERE user_id = $1'],
  ['preferences', 'SELECT * FROM preferences WHERE user_id = $1'],
  ['jobs', 'SELECT * FROM jobs WHERE user_id = $1 ORDER BY created_at'],
  ['stageEvents', 'SELECT * FROM job_stage_events WHERE user_id = $1 ORDER BY created_at'],
  ['postings', 'SELECT * FROM job_postings WHERE user_id = $1 ORDER BY created_at'],
  ['evaluations', 'SELECT * FROM evaluations WHERE user_id = $1 ORDER BY created_at'],
  ['cvVersions', 'SELECT * FROM cv_versions WHERE user_id = $1 ORDER BY created_at'],
  ['documents', 'SELECT * FROM documents WHERE user_id = $1 ORDER BY created_at'],
  ['stories', 'SELECT * FROM stories WHERE user_id = $1 ORDER BY created_at'],
  ['assistantThreads', 'SELECT * FROM assistant_threads WHERE user_id = $1 ORDER BY created_at'],
  ['assistantMessages', 'SELECT * FROM assistant_messages WHERE user_id = $1 ORDER BY created_at'],
  ['consents', 'SELECT * FROM consents WHERE user_id = $1 ORDER BY granted_at'],
  ['aiUsage', 'SELECT * FROM usage_counters WHERE user_id = $1 ORDER BY period'],
] as const;

export function registerAccountRoutes(app: FastifyInstance, ctx: RouteContext) {
  app.get('/account/export', async (req, reply) => {
    const auth = requireAuth(req);
    const data = await ctx.db.forUser(auth.userId, async (tx) => {
      const out: Record<string, unknown> = {
        exportedAt: new Date().toISOString(),
        format: 'career-ops-pocket-export@1',
        account: { email: auth.email, plan: auth.plan },
      };
      for (const [key, sql] of EXPORT_TABLES) {
        const r = await tx.query(sql, [auth.userId]);
        out[key] = key === 'profile' || key === 'preferences' ? r.rows[0] ?? null : r.rows;
      }
      return out;
    });
    await audit(ctx.db.pool, actorHash(auth.userId), 'account.export');
    reply.header('content-disposition', 'attachment; filename="career-ops-pocket-export.json"');
    return data;
  });

  /**
   * Permanently deletes the account: all workspace data (cascading from users), then the
   * Entra identity when Graph is configured. Data deletion happens first so a Graph outage
   * can never leave career data behind.
   */
  app.delete('/account', async (req, reply) => {
    const auth = requireAuth(req);
    parseWith(deleteBody, req.body);
    const hash = actorHash(auth.userId);
    await deleteUser(ctx.db.pool, auth.userId);
    ctx.forgetUser(auth.oid);
    let identity: 'deleted' | 'pending' | 'not_configured' = 'not_configured';
    if (ctx.graph) {
      try {
        await ctx.graph.deleteUser(auth.oid);
        identity = 'deleted';
      } catch (err) {
        identity = 'pending';
        req.log.error({ err }, 'identity deletion failed; data already deleted');
      }
    }
    await audit(ctx.db.pool, hash, 'account.delete', { identity });
    return reply.code(200).send({ deleted: true, identity });
  });
}
