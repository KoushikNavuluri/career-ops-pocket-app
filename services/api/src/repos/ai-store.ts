/** Postgres implementation of the AI gateway's consent, quota and metering store. */
import type { Db } from '../db/pool.ts';
import type { GatewayStore } from '../ai/gateway.ts';

export function createGatewayStore(db: Db): GatewayStore {
  return {
    async hasConsent(userId, feature, policyVersion) {
      return db.forUser(userId, async (tx) => {
        const r = await tx.query(
          'SELECT 1 FROM consents WHERE user_id = $1 AND feature = $2 AND policy_version = $3 AND revoked_at IS NULL',
          [userId, feature, policyVersion],
        );
        return (r.rowCount ?? 0) > 0;
      });
    },
    async recordConsent(userId, feature, policyVersion) {
      await db.forUser(userId, (tx) =>
        tx.query(
          `INSERT INTO consents (user_id, feature, policy_version) VALUES ($1, $2, $3)
           ON CONFLICT (user_id, feature, policy_version) WHERE revoked_at IS NULL DO NOTHING`,
          [userId, feature, policyVersion],
        ),
      );
    },
    async reserveCredits(userId, period, credits, limit) {
      return db.forUser(userId, async (tx) => {
        const r = await tx.query(
          `INSERT INTO usage_counters (user_id, period, credits_used)
           SELECT $1::uuid, $2::text, $3::int WHERE $3::int <= $4::int
           ON CONFLICT (user_id, period) DO UPDATE
             SET credits_used = usage_counters.credits_used + EXCLUDED.credits_used
             WHERE usage_counters.credits_used + EXCLUDED.credits_used <= $4::int
           RETURNING credits_used`,
          [userId, period, credits, limit],
        );
        return (r.rowCount ?? 0) > 0;
      });
    },
    async refundCredits(userId, period, credits) {
      await db.forUser(userId, (tx) =>
        tx.query(
          'UPDATE usage_counters SET credits_used = greatest(0, credits_used - $3::int) WHERE user_id = $1 AND period = $2',
          [userId, period, credits],
        ),
      );
    },
    async recordRun(run) {
      return db.forUser(run.userId, async (tx) => {
        const r = await tx.query<{ id: string }>(
          `INSERT INTO ai_runs (user_id, feature, model, prompt_version, input_tokens, output_tokens, cached_tokens,
             reasoning_tokens, credits, latency_ms, status, error_code)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12) RETURNING id`,
          [
            run.userId,
            run.feature,
            run.model,
            run.promptVersion,
            run.usage.inputTokens,
            run.usage.outputTokens,
            run.usage.cachedInputTokens,
            run.usage.reasoningTokens,
            run.credits,
            run.latencyMs,
            run.status,
            run.errorCode,
          ],
        );
        return r.rows[0]!.id;
      });
    },
  };
}
