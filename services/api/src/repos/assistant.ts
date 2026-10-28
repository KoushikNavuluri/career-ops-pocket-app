import type { Tx } from '../db/pool.ts';

export type ThreadRow = { id: string; title: string; context_job_id: string | null; created_at: Date; updated_at: Date };
export type MessageRow = { id: string; thread_id: string; role: 'user' | 'assistant'; content: string; created_at: Date };

export async function listThreads(tx: Tx, userId: string): Promise<ThreadRow[]> {
  const r = await tx.query<ThreadRow>(
    'SELECT id, title, context_job_id, created_at, updated_at FROM assistant_threads WHERE user_id = $1 ORDER BY updated_at DESC LIMIT 100',
    [userId],
  );
  return r.rows;
}

export async function getThread(tx: Tx, userId: string, id: string): Promise<ThreadRow | null> {
  const r = await tx.query<ThreadRow>(
    'SELECT id, title, context_job_id, created_at, updated_at FROM assistant_threads WHERE id = $1 AND user_id = $2',
    [id, userId],
  );
  return r.rows[0] ?? null;
}

export async function createThread(tx: Tx, userId: string, contextJobId: string | null): Promise<ThreadRow> {
  const r = await tx.query<ThreadRow>(
    'INSERT INTO assistant_threads (user_id, context_job_id) VALUES ($1, $2) RETURNING id, title, context_job_id, created_at, updated_at',
    [userId, contextJobId],
  );
  return r.rows[0]!;
}

export async function updateThread(tx: Tx, userId: string, id: string, patch: { title?: string; contextJobId?: string | null }): Promise<void> {
  await tx.query(
    `UPDATE assistant_threads SET
       title = coalesce($3, title),
       context_job_id = CASE WHEN $4::boolean THEN $5::uuid ELSE context_job_id END
     WHERE id = $1 AND user_id = $2`,
    [id, userId, patch.title ?? null, patch.contextJobId !== undefined, patch.contextJobId ?? null],
  );
}

export async function deleteThread(tx: Tx, userId: string, id: string): Promise<boolean> {
  const r = await tx.query('DELETE FROM assistant_threads WHERE id = $1 AND user_id = $2', [id, userId]);
  return (r.rowCount ?? 0) > 0;
}

export async function listMessages(tx: Tx, userId: string, threadId: string, limit = 200): Promise<MessageRow[]> {
  const r = await tx.query<MessageRow>(
    `SELECT id, thread_id, role, content, created_at FROM (
       SELECT id, thread_id, role, content, created_at FROM assistant_messages
       WHERE thread_id = $1 AND user_id = $2 ORDER BY created_at DESC LIMIT $3
     ) m ORDER BY created_at ASC`,
    [threadId, userId, limit],
  );
  return r.rows;
}

export async function addMessage(tx: Tx, userId: string, threadId: string, role: 'user' | 'assistant', content: string, aiRunId: string | null): Promise<MessageRow> {
  const r = await tx.query<MessageRow>(
    `INSERT INTO assistant_messages (user_id, thread_id, role, content, ai_run_id) VALUES ($1, $2, $3, $4, $5)
     RETURNING id, thread_id, role, content, created_at`,
    [userId, threadId, role, content, aiRunId],
  );
  await tx.query('UPDATE assistant_threads SET updated_at = now() WHERE id = $1 AND user_id = $2', [threadId, userId]);
  return r.rows[0]!;
}
