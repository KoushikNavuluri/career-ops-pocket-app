/**
 * In-process sliding-window limiter for burst protection. Per replica, so it is a
 * first line of defence only; monthly AI quotas are enforced in Postgres.
 */
export function createRateLimiter(now: () => number = () => Date.now()) {
  const hits = new Map<string, number[]>();
  let lastSweep = now();

  function sweep(windowMs: number) {
    const t = now();
    if (t - lastSweep < windowMs) return;
    lastSweep = t;
    for (const [key, times] of hits) {
      const fresh = times.filter((x) => t - x < windowMs);
      if (fresh.length) hits.set(key, fresh);
      else hits.delete(key);
    }
  }

  return {
    /** Returns seconds until retry, or 0 when the hit is allowed (and recorded). */
    hit(key: string, limit: number, windowMs = 60_000): number {
      sweep(windowMs);
      const t = now();
      const times = (hits.get(key) ?? []).filter((x) => t - x < windowMs);
      if (times.length >= limit) {
        const retryMs = windowMs - (t - times[0]!);
        hits.set(key, times);
        return Math.max(1, Math.ceil(retryMs / 1000));
      }
      times.push(t);
      hits.set(key, times);
      return 0;
    },
    size: () => hits.size,
  };
}

export type RateLimiter = ReturnType<typeof createRateLimiter>;
