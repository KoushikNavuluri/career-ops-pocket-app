import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { createHash } from 'node:crypto';
import type { Config } from './config.ts';
import type { Db } from './db/pool.ts';
import type { Claims, TokenVerifier } from './http/auth.ts';
import type { Gateway } from './ai/gateway.ts';
import type { GraphClient } from './integrations/graph.ts';
import { AppError, forbidden, toProblem, unauthorized } from './http/errors.ts';
import { createRateLimiter, type RateLimiter } from './http/rate-limit.ts';
import { upsertUserByOid, type UserRow } from './repos/users.ts';
import { registerProfileRoutes } from './routes/profile.ts';
import { registerJobRoutes } from './routes/jobs.ts';
import { registerContentRoutes } from './routes/content.ts';
import { registerAiRoutes } from './routes/ai.ts';
import { registerAssistantRoutes } from './routes/assistant.ts';
import { registerAccountRoutes } from './routes/account.ts';

export type AuthContext = { userId: string; oid: string; plan: string; email: string | null; roles: string[] };

declare module 'fastify' {
  interface FastifyRequest {
    auth: AuthContext | null;
  }
}

export type Deps = {
  config: Config;
  db: Db;
  verifyToken: TokenVerifier;
  gateway: Gateway;
  graph?: GraphClient;
};

export type RouteContext = Deps & {
  limiter: RateLimiter;
  /** Throws 429 when the caller exceeds `limit` hits per minute in `bucket`. */
  limit(req: FastifyRequest, bucket: string, limit: number): void;
  forgetUser(oid: string): void;
};

export function requireAuth(req: FastifyRequest): AuthContext {
  if (!req.auth) throw unauthorized();
  return req.auth;
}

export function actorHash(userId: string): string {
  return createHash('sha256').update(`pocket:${userId}`).digest('hex').slice(0, 32);
}

export async function buildApp(deps: Deps): Promise<FastifyInstance> {
  const app = Fastify({
    logger: {
      level: deps.config.logLevel,
      redact: { paths: ['req.headers.authorization', 'req.headers.cookie'], remove: true },
    },
    bodyLimit: 1_048_576,
    trustProxy: true,
    requestIdHeader: 'x-request-id',
    disableRequestLogging: deps.config.env === 'test',
  });

  app.decorateRequest('auth', null);

  app.setErrorHandler((error, request, reply) => {
    const problem = toProblem(error);
    if (problem.status >= 500) request.log.error({ err: error, code: problem.code }, 'request failed');
    else request.log.info({ code: problem.code, status: problem.status }, 'request rejected');
    if (problem.status === 429 && typeof problem.retryAfter === 'number') reply.header('retry-after', String(problem.retryAfter));
    reply.code(problem.status).type('application/problem+json').send(problem);
  });

  app.setNotFoundHandler((_request, reply) => {
    reply.code(404).type('application/problem+json').send(toProblem(new AppError(404, 'not_found', 'Route not found.')));
  });

  app.addHook('onSend', async (_req, reply, payload) => {
    reply.header('x-content-type-options', 'nosniff');
    reply.header('cache-control', reply.getHeader('cache-control') ?? 'no-store');
    return payload;
  });

  app.get('/healthz', async () => ({ ok: true }));
  app.get('/readyz', async () => {
    await deps.db.pool.query('SELECT 1');
    return { ok: true };
  });

  const limiter = createRateLimiter();
  const userCache = new Map<string, { user: UserRow; expires: number }>();
  const USER_CACHE_MS = 5 * 60 * 1000;

  async function resolveUser(claims: { oid: string; email?: string; name?: string }): Promise<UserRow> {
    const hit = userCache.get(claims.oid);
    if (hit && hit.expires > Date.now()) return hit.user;
    const user = await upsertUserByOid(deps.db.pool, claims);
    if (userCache.size > 10_000) userCache.clear();
    userCache.set(claims.oid, { user, expires: Date.now() + USER_CACHE_MS });
    return user;
  }

  const ctx: RouteContext = {
    ...deps,
    limiter,
    limit(req, bucket, limit) {
      const auth = requireAuth(req);
      const retryAfter = limiter.hit(`${bucket}:${auth.userId}`, limit);
      if (retryAfter > 0) {
        throw new AppError(429, 'rate_limited', 'You are going a bit fast. Try again in a moment.', { extra: { retryAfter } });
      }
    },
    forgetUser(oid) {
      userCache.delete(oid);
    },
  };

  await app.register(
    async (v1) => {
      v1.addHook('onRequest', async (req) => {
        const header = req.headers.authorization;
        if (!header || !header.startsWith('Bearer ')) throw unauthorized();
        let claims: Claims;
        try {
          claims = await deps.verifyToken(header.slice('Bearer '.length).trim());
        } catch {
          throw unauthorized('Your session has expired. Sign in again.');
        }
        const user = await resolveUser(claims);
        if (user.status !== 'active') throw forbidden('This account is suspended. Contact support.');
        req.auth = { userId: user.id, oid: claims.oid, plan: user.plan, email: user.email, roles: claims.roles };
      });

      v1.addHook('preHandler', async (req) => {
        if (req.method !== 'GET' && req.method !== 'HEAD') ctx.limit(req, 'writes', deps.config.rateLimits.writesPerMinute);
      });

      registerProfileRoutes(v1, ctx);
      registerJobRoutes(v1, ctx);
      registerContentRoutes(v1, ctx);
      registerAiRoutes(v1, ctx);
      registerAssistantRoutes(v1, ctx);
      registerAccountRoutes(v1, ctx);
    },
    { prefix: '/v1' },
  );

  return app;
}
