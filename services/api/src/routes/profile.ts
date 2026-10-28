import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { requireAuth, type RouteContext } from '../app.ts';
import { parseWith, optionalText } from '../http/validate.ts';
import { getPreferences, getProfile, updatePreferences, updateProfile } from '../repos/profile.ts';
import { currentMasterCv } from '../repos/content.ts';
import { listJobs } from '../repos/jobs.ts';
import { buildToday } from '../domain/today.ts';
import { usagePeriod } from '../ai/features.ts';

const keywords = z.array(z.string().trim().min(1).max(60)).max(30);

const profilePatch = z
  .object({
    alias: optionalText(80),
    target_role: optionalText(120),
    north_star: optionalText(2000),
    target_market: z.enum(['Europe', 'United States', 'India', 'Global']).nullable().optional(),
    work_model: z.enum(['Remote', 'Hybrid', 'On-site']).nullable().optional(),
    target_base: z.number().nonnegative().max(1e12).nullable().optional(),
    currency: z.enum(['EUR', 'USD', 'GBP', 'INR']).nullable().optional(),
    include_keywords: keywords.optional(),
    exclude_keywords: keywords.optional(),
    work_auth_check: z.enum(['Verify per role', 'No sponsorship stated', 'Sponsorship stated']).optional(),
    onboarded: z.boolean().optional(),
  })
  .strict();

const preferencesPatch = z
  .object({
    theme: z.enum(['system', 'light', 'evening']).optional(),
    resume_template: z.enum(['editorial', 'minimal', 'technical']).optional(),
    export_format: z.enum(['pdf', 'markdown', 'latex']).optional(),
    posting_verification: z.boolean().optional(),
    weekly_scan: z.boolean().optional(),
  })
  .strict();

export function registerProfileRoutes(app: FastifyInstance, ctx: RouteContext) {
  app.get('/me', async (req) => {
    const auth = requireAuth(req);
    return ctx.db.forUser(auth.userId, async (tx) => {
      const [profile, preferences, usage] = await Promise.all([
        getProfile(tx, auth.userId),
        getPreferences(tx, auth.userId),
        tx.query<{ credits_used: number }>('SELECT credits_used FROM usage_counters WHERE user_id = $1 AND period = $2', [
          auth.userId,
          usagePeriod(),
        ]),
      ]);
      return {
        user: { id: auth.userId, email: auth.email, plan: auth.plan },
        onboarded: Boolean(profile?.onboarded_at),
        profile,
        preferences,
        usage: {
          period: usagePeriod(),
          used: usage.rows[0]?.credits_used ?? 0,
          limit: ctx.config.credits[auth.plan] ?? ctx.config.credits.free ?? 0,
        },
      };
    });
  });

  app.patch('/profile', async (req) => {
    const auth = requireAuth(req);
    const patch = parseWith(profilePatch, req.body);
    return ctx.db.forUser(auth.userId, (tx) => updateProfile(tx, auth.userId, patch));
  });

  app.patch('/preferences', async (req) => {
    const auth = requireAuth(req);
    const patch = parseWith(preferencesPatch, req.body);
    return ctx.db.forUser(auth.userId, (tx) => updatePreferences(tx, auth.userId, patch));
  });

  app.get('/today', async (req) => {
    const auth = requireAuth(req);
    return ctx.db.forUser(auth.userId, async (tx) => {
      const [jobs, cv] = await Promise.all([listJobs(tx, auth.userId, { sort: 'recent', limit: 500 }), currentMasterCv(tx, auth.userId)]);
      return buildToday(
        jobs.map((j) => ({
          id: j.id,
          company: j.company,
          role: j.role,
          status: j.status,
          score: j.score,
          saved: j.saved,
          last_event_at: j.last_event_at,
        })),
        { hasCv: Boolean(cv?.markdown.trim()) },
      );
    });
  });
}
