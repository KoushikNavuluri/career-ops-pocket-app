/** Server-side context assembly. The client sends ids, never raw context. */
export type ProfileContext = {
  alias: string | null;
  target_role: string | null;
  north_star: string | null;
  target_market: string | null;
  work_model: string | null;
  target_base: number | string | null;
  currency: string | null;
  include_keywords: string[];
  exclude_keywords: string[];
  work_auth_check: string | null;
};

export type JobContext = {
  id: string;
  company: string;
  role: string;
  location: string | null;
  work_model: string | null;
  salary_text: string | null;
  description: string;
  status: string;
  score: number | null;
};

export type StoryContext = { title: string; competency: string; situation: string; task: string; action: string; result: string };

export const LIMITS = {
  cvChars: 14_000,
  jobChars: 16_000,
  storyChars: 5_000,
  historyChars: 12_000,
  historyMessages: 12,
  pipelineRows: 25,
};

export function truncate(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}\n[truncated: ${text.length - max} more characters]`;
}

/** Remove our own wrapper tags so untrusted text can't close them early. */
export function neutralizeTags(text: string): string {
  return text.replace(/<\/?\s*(job_posting|document|pasted|cv|profile|stories|workspace)\b[^>]*>/gi, '[tag removed]');
}

export function profileBlock(p: ProfileContext | null): string {
  if (!p) return '<profile>No profile saved yet.</profile>';
  const lines = [
    `Alias: ${p.alias ?? 'unknown'}`,
    `Target role: ${p.target_role ?? 'unknown'}`,
    `North star: ${p.north_star ?? 'not stated'}`,
    `Target market: ${p.target_market ?? 'unknown'}`,
    `Preferred work model: ${p.work_model ?? 'unknown'}`,
    `Target base: ${p.target_base ?? 'not stated'} ${p.currency ?? ''}`.trim(),
    `Include title keywords: ${p.include_keywords.join(', ') || 'none'}`,
    `Exclude title keywords: ${p.exclude_keywords.join(', ') || 'none'}`,
    `Work authorization: ${p.work_auth_check ?? 'verify per role'}`,
  ];
  return `<profile>\n${lines.join('\n')}\n</profile>`;
}

export function cvBlock(markdown: string | null): string {
  if (!markdown || !markdown.trim()) return '<cv>No CV saved. Treat all CV evidence as unknown.</cv>';
  return `<cv>\n${truncate(neutralizeTags(markdown.trim()), LIMITS.cvChars)}\n</cv>`;
}

export function jobBlock(job: JobContext): string {
  const meta = [
    `Company: ${job.company}`,
    `Role: ${job.role}`,
    `Location: ${job.location ?? 'not stated'}`,
    `Work model: ${job.work_model ?? 'not stated'}`,
    `Advertised compensation: ${job.salary_text ?? 'not stated'}`,
  ].join('\n');
  return `<job_posting>\n${meta}\n\n${truncate(neutralizeTags(job.description), LIMITS.jobChars)}\n</job_posting>`;
}

export function storiesBlock(stories: StoryContext[]): string {
  if (stories.length === 0) return '<stories>No stories saved.</stories>';
  let out = '';
  for (const s of stories) {
    const entry = `- ${s.title} [${s.competency}]\n  S: ${s.situation}\n  T: ${s.task}\n  A: ${s.action}\n  R: ${s.result}\n`;
    if (out.length + entry.length > LIMITS.storyChars) break;
    out += entry;
  }
  return `<stories>\n${neutralizeTags(out.trim())}\n</stories>`;
}

export function pipelineBlock(jobs: Array<Pick<JobContext, 'company' | 'role' | 'status' | 'score'>>): string {
  if (jobs.length === 0) return '<workspace>The pipeline is empty.</workspace>';
  const rows = jobs
    .slice(0, LIMITS.pipelineRows)
    .map((j) => `- ${j.company} · ${j.role} · ${j.status}${j.score != null ? ` · score ${Number(j.score).toFixed(1)}` : ''}`);
  const more = jobs.length > LIMITS.pipelineRows ? `\n(${jobs.length - LIMITS.pipelineRows} more roles not shown)` : '';
  return `<workspace>\nPipeline (most recent first):\n${neutralizeTags(rows.join('\n'))}${more}\n</workspace>`;
}

/** Keep the most recent messages that fit the budget, oldest first. */
export function trimHistory<T extends { role: string; content: string }>(messages: T[]): T[] {
  const out: T[] = [];
  let total = 0;
  for (let i = messages.length - 1; i >= 0 && out.length < LIMITS.historyMessages; i--) {
    const m = messages[i]!;
    if (total + m.content.length > LIMITS.historyChars) break;
    total += m.content.length;
    out.unshift(m);
  }
  return out;
}
