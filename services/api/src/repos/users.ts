import type pg from 'pg';

export type UserRow = {
  id: string;
  entra_oid: string;
  email: string | null;
  display_name: string | null;
  plan: string;
  status: string;
  created_at: Date;
};

/** Find-or-create by Entra object id. Also creates empty profile and preferences rows. */
export async function upsertUserByOid(
  pool: pg.Pool,
  claims: { oid: string; email?: string; name?: string },
): Promise<UserRow> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const existing = await client.query<UserRow>('SELECT * FROM users WHERE entra_oid = $1', [claims.oid]);
    let user = existing.rows[0];
    if (!user) {
      const inserted = await client.query<UserRow>(
        `INSERT INTO users (entra_oid, email, display_name) VALUES ($1, $2, $3)
         ON CONFLICT (entra_oid) DO UPDATE SET entra_oid = EXCLUDED.entra_oid
         RETURNING *`,
        [claims.oid, claims.email ?? null, claims.name ?? null],
      );
      user = inserted.rows[0]!;
      await client.query("SELECT set_config('app.user_id', $1, true)", [user.id]);
      await client.query('INSERT INTO profiles (user_id, alias) VALUES ($1, $2) ON CONFLICT DO NOTHING', [user.id, claims.name ?? null]);
      await client.query('INSERT INTO preferences (user_id) VALUES ($1) ON CONFLICT DO NOTHING', [user.id]);
    } else if (claims.email && claims.email !== user.email) {
      await client.query('UPDATE users SET email = $2 WHERE id = $1', [user.id, claims.email]);
      user = { ...user, email: claims.email };
    }
    await client.query('COMMIT');
    return user;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw err;
  } finally {
    client.release();
  }
}

export async function deleteUser(pool: pg.Pool, userId: string): Promise<void> {
  await pool.query('DELETE FROM users WHERE id = $1', [userId]);
}

export async function audit(pool: pg.Pool, actorHash: string, action: string, detail: Record<string, unknown> = {}): Promise<void> {
  await pool.query('INSERT INTO audit_events (actor_hash, action, detail) VALUES ($1, $2, $3)', [actorHash, action, JSON.stringify(detail)]);
}
