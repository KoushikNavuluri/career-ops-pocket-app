import type { Tx } from '../db/pool.ts';

export type CvRow = { id: string; kind: string; job_id: string | null; markdown: string; source: string; is_current: boolean; created_at: Date };

export async function currentMasterCv(tx: Tx, userId: string): Promise<CvRow | null> {
  const r = await tx.query<CvRow>(
    `SELECT id, kind, job_id, markdown, source, is_current, created_at FROM cv_versions
     WHERE user_id = $1 AND kind = 'master' AND is_current`,
    [userId],
  );
  return r.rows[0] ?? null;
}

export async function saveMasterCv(tx: Tx, userId: string, markdown: string, source: string): Promise<CvRow> {
  await tx.query(`UPDATE cv_versions SET is_current = false WHERE user_id = $1 AND kind = 'master' AND is_current`, [userId]);
  const r = await tx.query<CvRow>(
    `INSERT INTO cv_versions (user_id, kind, markdown, source, is_current) VALUES ($1, 'master', $2, $3, true)
     RETURNING id, kind, job_id, markdown, source, is_current, created_at`,
    [userId, markdown, source],
  );
  return r.rows[0]!;
}

export async function listCvVersions(tx: Tx, userId: string, limit = 50): Promise<Array<Omit<CvRow, 'markdown'> & { chars: number }>> {
  const r = await tx.query<Omit<CvRow, 'markdown'> & { chars: number }>(
    `SELECT id, kind, job_id, source, is_current, created_at, char_length(markdown) AS chars FROM cv_versions
     WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2`,
    [userId, limit],
  );
  return r.rows;
}

export async function getCvVersion(tx: Tx, userId: string, id: string): Promise<CvRow | null> {
  const r = await tx.query<CvRow>(
    'SELECT id, kind, job_id, markdown, source, is_current, created_at FROM cv_versions WHERE id = $1 AND user_id = $2',
    [id, userId],
  );
  return r.rows[0] ?? null;
}

export type StoryRow = {
  id: string;
  title: string;
  competency: string;
  situation: string;
  task: string;
  action: string;
  result: string;
  reflection: string;
  version: number;
  created_at: Date;
  updated_at: Date;
};

export type StoryInput = Omit<StoryRow, 'id' | 'version' | 'created_at' | 'updated_at'>;

export async function listStories(tx: Tx, userId: string): Promise<StoryRow[]> {
  const r = await tx.query<StoryRow>(
    `SELECT id, title, competency, situation, task, action, result, reflection, version, created_at, updated_at
     FROM stories WHERE user_id = $1 ORDER BY updated_at DESC`,
    [userId],
  );
  return r.rows;
}

export async function insertStory(tx: Tx, userId: string, s: StoryInput): Promise<StoryRow> {
  const r = await tx.query<StoryRow>(
    `INSERT INTO stories (user_id, title, competency, situation, task, action, result, reflection)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
     RETURNING id, title, competency, situation, task, action, result, reflection, version, created_at, updated_at`,
    [userId, s.title, s.competency, s.situation, s.task, s.action, s.result, s.reflection],
  );
  return r.rows[0]!;
}

export async function updateStory(tx: Tx, userId: string, id: string, s: StoryInput): Promise<StoryRow | null> {
  const r = await tx.query<StoryRow>(
    `UPDATE stories SET title = $3, competency = $4, situation = $5, task = $6, action = $7, result = $8, reflection = $9,
       version = version + 1
     WHERE id = $1 AND user_id = $2
     RETURNING id, title, competency, situation, task, action, result, reflection, version, created_at, updated_at`,
    [id, userId, s.title, s.competency, s.situation, s.task, s.action, s.result, s.reflection],
  );
  return r.rows[0] ?? null;
}

export async function deleteStory(tx: Tx, userId: string, id: string): Promise<boolean> {
  const r = await tx.query('DELETE FROM stories WHERE id = $1 AND user_id = $2', [id, userId]);
  return (r.rowCount ?? 0) > 0;
}

export type DocumentRow = {
  id: string;
  job_id: string | null;
  type: string;
  title: string;
  body_md: string;
  ai_run_id: string | null;
  created_at: Date;
  updated_at: Date;
};

export async function listDocuments(tx: Tx, userId: string, jobId?: string): Promise<Array<Omit<DocumentRow, 'body_md'>>> {
  const values: unknown[] = [userId];
  let where = 'user_id = $1';
  if (jobId) {
    values.push(jobId);
    where += ' AND job_id = $2';
  }
  const r = await tx.query<Omit<DocumentRow, 'body_md'>>(
    `SELECT id, job_id, type, title, ai_run_id, created_at, updated_at FROM documents WHERE ${where} ORDER BY created_at DESC LIMIT 200`,
    values,
  );
  return r.rows;
}

export async function getDocument(tx: Tx, userId: string, id: string): Promise<DocumentRow | null> {
  const r = await tx.query<DocumentRow>('SELECT * FROM documents WHERE id = $1 AND user_id = $2', [id, userId]);
  return r.rows[0] ?? null;
}

export async function insertDocument(
  tx: Tx,
  userId: string,
  d: { jobId: string | null; type: string; title: string; body: string; aiRunId: string | null },
): Promise<DocumentRow> {
  const r = await tx.query<DocumentRow>(
    `INSERT INTO documents (user_id, job_id, type, title, body_md, ai_run_id) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *`,
    [userId, d.jobId, d.type, d.title.slice(0, 300), d.body, d.aiRunId],
  );
  return r.rows[0]!;
}

export async function updateDocument(tx: Tx, userId: string, id: string, patch: { title?: string; body?: string }): Promise<DocumentRow | null> {
  const r = await tx.query<DocumentRow>(
    `UPDATE documents SET title = coalesce($3, title), body_md = coalesce($4, body_md) WHERE id = $1 AND user_id = $2 RETURNING *`,
    [id, userId, patch.title ?? null, patch.body ?? null],
  );
  return r.rows[0] ?? null;
}

export async function deleteDocument(tx: Tx, userId: string, id: string): Promise<boolean> {
  const r = await tx.query('DELETE FROM documents WHERE id = $1 AND user_id = $2', [id, userId]);
  return (r.rowCount ?? 0) > 0;
}
