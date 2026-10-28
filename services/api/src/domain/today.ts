/** Server-computed "Today" view: counts, strong matches and next best moves. */
import type { JobStatus } from './statuses.ts';

export type TodayJob = {
  id: string;
  company: string;
  role: string;
  status: JobStatus;
  score: number | null;
  saved: boolean;
  last_event_at: Date | string;
};

export type NextMove = {
  kind: 'review_inbox' | 'prepare_application' | 'follow_up' | 'prepare_interview' | 'add_first_role' | 'add_cv';
  title: string;
  detail: string;
  jobId?: string;
};

export type TodayView = {
  counts: { inbox: number; pipeline: number; interview: number; offer: number; strongMatches: number };
  strongMatches: Array<Pick<TodayJob, 'id' | 'company' | 'role' | 'score' | 'status'>>;
  nextMoves: NextMove[];
};

const DAY_MS = 24 * 60 * 60 * 1000;
export const FOLLOW_UP_AFTER_DAYS = 7;
export const STRONG_MATCH_SCORE = 4;

export function buildToday(jobs: TodayJob[], opts: { hasCv: boolean; now?: Date }): TodayView {
  const now = opts.now ?? new Date();
  const inbox = jobs.filter((j) => j.status === 'Inbox');
  const pipeline = jobs.filter((j) => ['Applied', 'Responded', 'Interview', 'Offer'].includes(j.status));
  const interview = jobs.filter((j) => j.status === 'Interview');
  const offer = jobs.filter((j) => j.status === 'Offer');
  const strong = jobs
    .filter((j) => j.status === 'Evaluated' && (j.score ?? 0) >= STRONG_MATCH_SCORE)
    .sort((a, b) => (b.score ?? 0) - (a.score ?? 0));

  const moves: NextMove[] = [];
  if (!opts.hasCv) {
    moves.push({
      kind: 'add_cv',
      title: 'Add your master CV',
      detail: 'Evaluations and tailoring only use evidence from your CV.',
    });
  }
  if (jobs.length === 0) {
    moves.push({
      kind: 'add_first_role',
      title: 'Add your first opportunity',
      detail: 'Paste a job description to start your pipeline.',
    });
  }
  for (const j of strong.slice(0, 2)) {
    moves.push({
      kind: 'prepare_application',
      title: `Prepare your application to ${j.company}`,
      detail: `${j.role} scored ${j.score?.toFixed(1)}. Review the fit, then prepare your answers.`,
      jobId: j.id,
    });
  }
  for (const j of interview.slice(0, 2)) {
    moves.push({
      kind: 'prepare_interview',
      title: `Prepare for ${j.company}`,
      detail: `${j.role} is at interview stage.`,
      jobId: j.id,
    });
  }
  for (const j of jobs.filter((x) => x.status === 'Applied')) {
    const days = Math.floor((now.getTime() - new Date(j.last_event_at).getTime()) / DAY_MS);
    if (days >= FOLLOW_UP_AFTER_DAYS) {
      moves.push({
        kind: 'follow_up',
        title: `Follow up with ${j.company}`,
        detail: `You applied ${days} days ago with no recorded response.`,
        jobId: j.id,
      });
    }
  }
  if (inbox.length > 0) {
    moves.push({
      kind: 'review_inbox',
      title: `Review ${inbox.length} new ${inbox.length === 1 ? 'role' : 'roles'}`,
      detail: 'Evaluate or discard what is waiting in your inbox.',
    });
  }

  return {
    counts: {
      inbox: inbox.length,
      pipeline: pipeline.length,
      interview: interview.length,
      offer: offer.length,
      strongMatches: strong.length,
    },
    strongMatches: strong.slice(0, 3).map(({ id, company, role, score, status }) => ({ id, company, role, score, status })),
    nextMoves: moves.slice(0, 6),
  };
}
