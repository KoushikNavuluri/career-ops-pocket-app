/** Forward-only SQL migrations. Run before each deployment: `npm run migrate`. */
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import pg from 'pg';

const MIGRATIONS_DIR = fileURLToPath(new URL('../../migrations/', import.meta.url));

export async function runMigrations(pool: pg.Pool, log: (msg: string) => void = () => undefined): Promise<string[]> {
  const client = await pool.connect();
  const applied: string[] = [];
  try {
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      version text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`);
    // One migrator at a time across replicas.
    await client.query('SELECT pg_advisory_lock(727274)');
    const done = new Set((await client.query<{ version: string }>('SELECT version FROM schema_migrations')).rows.map((r) => r.version));
    const files = (await readdir(MIGRATIONS_DIR)).filter((f) => f.endsWith('.sql')).sort();
    for (const file of files) {
      const version = file.replace(/\.sql$/, '');
      if (done.has(version)) continue;
      const sql = await readFile(new URL(file, pathToFileURL(MIGRATIONS_DIR)), 'utf8');
      log(`applying ${version}`);
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations(version) VALUES ($1)', [version]);
        await client.query('COMMIT');
        applied.push(version);
      } catch (err) {
        await client.query('ROLLBACK');
        throw new Error(`Migration ${version} failed: ${(err as Error).message}`);
      }
    }
  } finally {
    await client.query('SELECT pg_advisory_unlock(727274)').catch(() => undefined);
    client.release();
  }
  return applied;
}

const isMain = process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  const url = process.env.DATABASE_URL;
  if (!url) {
    console.error('DATABASE_URL is required');
    process.exit(1);
  }
  const ssl = (process.env.DATABASE_SSL ?? 'false') === 'true';
  const pool = new pg.Pool({ connectionString: url, ssl: ssl ? { rejectUnauthorized: true } : false });
  runMigrations(pool, (m) => console.log(m))
    .then((applied) => console.log(applied.length ? `applied ${applied.length} migration(s)` : 'database is up to date'))
    .catch((err) => {
      console.error((err as Error).message);
      process.exitCode = 1;
    })
    .finally(() => pool.end());
}
