import type { Tx } from '../db/pool.ts';
import type { JobStatus, Actor } from '../domain/statuses.ts';
import { normalizeCompany, normalizeRole, sha256 } from '../domain/jobs.ts';

export type JobRow = {
  id: string;
  user_id: string;
  company: string;
  role: string;
  location: string | null;
  work_model: string | null;
  salary_text: string | null;
  source: string;
  source_url: string | null;
  external_id: string | null;
  description: string;
  status: JobStatus;
  saved: boolean;
  score: number | null;
  archetype: string | null;
  decision: string | null;
  legitimacy: string;
  work_auth: string;
  notes: string | null;
  version: number;
  created_at: Date;
  updated_at: Date;
};

export type JobSummaryRow = Omit<JobRow, 'description' | 'notes'> & { last_event_at: Date };

export type StageEventRow = {
  id: string;
  from_status: string | null;
  to_status: string;
  note: string | null;
  feedback: string | null;
  actor: Actor;
  created_at: Date;
};

export type ListFilter = {
  status?: JobStatus;
  saved?: boolean;
  q?: string;
  minScore?: number;
  workModel?: string;
  sort: 'recent' | 'score' | 'company';
  limit: number;
};

const SUMMARY_COLUMNS = `j.id, j.user_id, j.company, j.role, j.location, j.work_model, j.salary_text, j.source, j.source_url,
  j.external_id, j.status, j.saved, j.score, j.archetype, j.decision, j.legitimacy, j.work_auth, j.version,
  j.created_at, j.updated_at,
  coalesce((SELECT max(e.created_at) FROM job_stage_events e WHERE e.job_id = j.id), j.created_at) AS last_event_at`;

export async function listJobs(tx: Tx, userId: string, f: ListFilter): Promise<JobSummaryRow[]> {
  const where = ['j.user_id = $1'];
  const values: unknown[] = [userId];
  if (f.status) {
    values.push(f.status);
    where.push(`j.status = $${values.length}`);
  }
  if (f.saved !== undefined) {
    values.push(f.saved);
    where.push(`j.saved = $${values.length}`);
  }
  if (f.minScore !== undefined) {
    values.push(f.minScore);
    where.push(`j.score >= $${values.length}`);
  }
  if (f.workModel) {
    values.push(f.workModel);
    where.push(`j.work_model = $${values.length}`);
  }
  if (f.q) {
    values.push(`%${f.q.replace(/[\\%_]/g, (m) => `\\${m}`)}%`);
    where.push(`(j.company ILIKE $${values.length} OR j.role ILIKE $${values.length})`);
  }
  const order =
    f.sort === 'score'
      ? 'j.score DESC NULLS LAST, j.updated_at DESC'
      : f.sort === 'company'
        ? 'lower(j.company) ASC, j.updated_at DESC'
        : 'j.updated_at DESC';
  values.push(f.limit);
  const r = await tx.query<JobSummaryRow>(
    `SELECT ${SUMMARY_COLUMNS} FROM jobs j WHERE ${where.join(' AND ')} ORDER BY ${order} LIMIT $${values.length}`,
    values,
  );
  return r.rows;
}

export async function getJob(tx: Tx, userId: string, id: string): Promise<JobRow | null> {
  const r = await tx.query<JobRow>('SELECT * FROM jobs WHERE id = $1 AND user_id = $2', [id, userId]);
  return r.rows[0] ?? null;
}

export async function findDuplicate(tx: Tx, userId: string, company: string, role: string): Promise<{ id: string } | null> {
  const r = await tx.query<{ id: string; company: string; role: string }>(
    `SELECT id, company, role FROM jobs WHERE user_id = $1 AND status NOT IN ('Discarded', 'SKIP') AND lower(role) = lower($2)`,
    [userId, role.trim()],
  );
  const target = normalizeCompany(company);
  const targetRole = normalizeRole(role);
  const hit = r.rows.find((row) => normalizeCompany(row.company) === target && normalizeRole(row.role) === targetRole);
  return hit ? { id: hit.id } : null;
}

export type NewJob = {
  company: string;
  role: string;
  description: string;
  location?: string | null;
  work_model?: string | null;
  salary_text?: string | null;
  source_url?: string | null;
  source?: string;
  external_id?: string | null;
};

export async function insertJob(tx: Tx, userId: string, job: NewJob): Promise<JobRow> {
  const r = await tx.query<JobRow>(
    `INSERT INTO jobs (user_id, company, role, description, location, work_model, salary_text, source_url, source, external_id)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
    [
      userId,
      job.company.trim(),
      job.role.trim(),
      job.description,
      job.location ?? null,
      job.work_model ?? null,
      job.salary_text ?? null,
      job.source_url ?? null,
      job.source ?? 'pasted',
      job.external_id ?? null,
    ],
  );
  const row = r.rows[0]!;
  await tx.query(
    'INSERT INTO job_postings (user_id, job_id, text, sha256) VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING',
    [userId, row.id, job.description, sha256(job.description)],
  );
  await addStageEvent(tx, userId, row.id, null, 'Inbox', 'system', 'Added to inbox', null);
  return row;
}

export type JobPatch = Partial<{
  company: string;
  role: string;
  location: string | null;
  work_model: string | null;
  salary_text: string | null;
  notes: string | null;
  saved: boolean;
}>;

/** Optimistic concurrency: returns null when `expectedVersion` no longer matches. */
export async function updateJob(tx: Tx, userId: string, id: string, patch: JobPatch, expectedVersion?: number): Promise<JobRow | null> {
  const cols = ['company', 'role', 'location', 'work_model', 'salary_text', 'notes', 'saved'] as const;
  const sets: string[] = [];
  const values: unknown[] = [id, userId];
  for (const c of cols) {
    if (patch[c] !== undefined) {
      values.push(patch[c]);
      sets.push(`${c} = $${values.length}`);
    }
  }
  sets.push('version = version + 1');
  let versionClause = '';
  if (expectedVersion !== undefined) {
    values.push(expectedVersion);
    versionClause = ` AND version = $${values.length}`;
  }
  const r = await tx.query<JobRow>(
    `UPDATE jobs SET ${sets.join(', ')} WHERE id = $1 AND user_id = $2${versionClause} RETURNING *`,
    values,
  );
  return r.rows[0] ?? null;
}

export async function setStatus(tx: Tx, userId: string, id: string, status: JobStatus): Promise<JobRow> {
  const r = await tx.query<JobRow>(
    'UPDATE jobs SET status = $3, version = version + 1 WHERE id = $1 AND user_id = $2 RETURNING *',
    [id, userId, status],
  );
  return r.rows[0]!;
}

export async function applyEvaluation(
  tx: Tx,
  userId: string,
  id: string,
  e: { score: number; archetype: string; decision: string; legitimacy: string; workAuth: string },
): Promise<void> {
  await tx.query(
    `UPDATE jobs SET score = $3, archetype = $4, decision = $5, legitimacy = $6, work_auth = $7, version = version + 1
     WHERE id = $1 AND user_id = $2`,
    [id, userId, e.score, e.archetype, e.decision, e.legitimacy, e.workAuth],
  );
}

export async function addStageEvent(
  tx: Tx,
  userId: string,
  jobId: string,
  from: string | null,
  to: string,
  actor: Actor,
  note: string | null,
  feedback: string | null,
): Promise<void> {
  await tx.query(
    `INSERT INTO job_stage_events (user_id, job_id, from_status, to_status, actor, note, feedback)
     VALUES ($1, $2, $3, $4, $5, $6, $7)`,
    [userId, jobId, from, to, actor, note, feedback],
  );
}

export async function listStageEvents(tx: Tx, userId: string, jobId: string): Promise<StageEventRow[]> {
  const r = await tx.query<StageEventRow>(
    `SELECT id, from_status, to_status, note, feedback, actor, created_at FROM job_stage_events
     WHERE job_id = $1 AND user_id = $2 ORDER BY created_at ASC`,
    [jobId, userId],
  );
  return r.rows;
}

export async function deleteJob(tx: Tx, userId: string, id: string): Promise<boolean> {
  const r = await tx.query('DELETE FROM jobs WHERE id = $1 AND user_id = $2', [id, userId]);
  return (r.rowCount ?? 0) > 0;
}

export type EvaluationRow = {
  id: string;
  job_id: string;
  ai_run_id: string | null;
  score: number;
  archetype: string;
  decision: string;
  result: unknown;
  prompt_version: string;
  model: string;
  created_at: Date;
};

export async function insertEvaluation(
  tx: Tx,
  userId: string,
  jobId: string,
  e: { runId: string; score: number; archetype: string; decision: string; result: unknown; promptVersion: string; model: string },
): Promise<EvaluationRow> {
  const r = await tx.query<EvaluationRow>(
    `INSERT INTO evaluations (user_id, job_id, ai_run_id, score, archetype, decision, result, prompt_version, model)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     RETURNING id, job_id, ai_run_id, score, archetype, decision, result, prompt_version, model, created_at`,
    [userId, jobId, e.runId, e.score, e.archetype, e.decision, JSON.stringify(e.result), e.promptVersion, e.model],
  );
  return r.rows[0]!;
}

export async function latestEvaluation(tx: Tx, userId: string, jobId: string): Promise<EvaluationRow | null> {
  const r = await tx.query<EvaluationRow>(
    `SELECT id, job_id, ai_run_id, score, archetype, decision, result, prompt_version, model, created_at FROM evaluations
     WHERE job_id = $1 AND user_id = $2 ORDER BY created_at DESC LIMIT 1`,
    [jobId, userId],
  );
  return r.rows[0] ?? null;
}
