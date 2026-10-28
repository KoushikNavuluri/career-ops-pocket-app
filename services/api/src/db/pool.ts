import pg from 'pg';

// NUMERIC (score, target_base) -> number instead of string.
pg.types.setTypeParser(1700, (v: string) => Number.parseFloat(v));
// INT8 (count(*)) -> number. Safe for our counts.
pg.types.setTypeParser(20, (v: string) => Number.parseInt(v, 10));

export type Tx = pg.PoolClient;

export type Db = {
  pool: pg.Pool;
  /** Runs `fn` in a transaction with row-level security scoped to `userId`. */
  forUser<T>(userId: string, fn: (tx: Tx) => Promise<T>): Promise<T>;
  close(): Promise<void>;
};

export function createDb(opts: { connectionString: string; ssl: boolean; max?: number }): Db {
  const pool = new pg.Pool({
    connectionString: opts.connectionString,
    ssl: opts.ssl ? { rejectUnauthorized: true } : false,
    max: opts.max ?? 10,
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
    statement_timeout: 15_000,
  });

  async function forUser<T>(userId: string, fn: (tx: Tx) => Promise<T>): Promise<T> {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.user_id', $1, true)", [userId]);
      const result = await fn(client);
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw err;
    } finally {
      client.release();
    }
  }

  return { pool, forUser, close: () => pool.end() };
}
