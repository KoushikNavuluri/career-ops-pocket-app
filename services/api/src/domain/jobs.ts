/** Pure helpers for job records. No I/O. */
import { createHash } from 'node:crypto';

export const MIN_DESCRIPTION_CHARS = 60;
export const MAX_DESCRIPTION_CHARS = 60_000;
export const WORK_MODELS = ['Remote', 'Hybrid', 'On-site'] as const;
export type WorkModel = (typeof WORK_MODELS)[number];

export function normalizeCompany(value: string): string {
  return value
    .normalize('NFKC')
    .toLowerCase()
    .replace(/\b(inc|llc|ltd|gmbh|corp|corporation|co|plc|pvt|private|limited)\b\.?/g, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
}

export function normalizeRole(value: string): string {
  return value.normalize('NFKC').toLowerCase().replace(/\s+/g, ' ').trim();
}

export function sha256(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

/** Clean a pasted job description: normalise line endings, trim, collapse 3+ blank lines. */
export function cleanDescription(text: string): string {
  return text
    .replace(/\r\n?/g, '\n')
    .replace(/[ \t\u00a0]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function csvEscape(value: unknown): string {
  if (value === null || value === undefined) return '';
  let s = String(value);
  // Guard against CSV formula injection when opened in spreadsheets.
  if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`;
  if (/[",\n\r]/.test(s)) s = `"${s.replace(/"/g, '""')}"`;
  return s;
}

export type CsvJob = {
  company: string;
  role: string;
  status: string;
  score: number | null;
  salary_text: string | null;
  location: string | null;
  created_at: Date | string;
};

export function jobsToCsv(rows: CsvJob[]): string {
  const header = ['Company', 'Role', 'Status', 'Score', 'Salary', 'Location', 'Date'];
  const lines = rows.map((r) =>
    [
      r.company,
      r.role,
      r.status,
      r.status === 'Inbox' ? '' : r.score ?? '',
      r.salary_text ?? '',
      r.location ?? '',
      new Date(r.created_at).toISOString().slice(0, 10),
    ]
      .map(csvEscape)
      .join(','),
  );
  return [header.join(','), ...lines].join('\n') + '\n';
}
