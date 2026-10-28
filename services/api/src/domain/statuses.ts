/**
 * Job pipeline statuses and the transitions the server allows.
 * The client never decides what is legal; it asks the API (`allowedTransitions`).
 */
export const STATUSES = [
  'Inbox',
  'Evaluated',
  'Applied',
  'Responded',
  'Interview',
  'Offer',
  'Hired',
  'Rejected',
  'Discarded',
  'SKIP',
] as const;

export type JobStatus = (typeof STATUSES)[number];

export type Actor = 'user' | 'system';

/** Statuses only the system may set (evaluation sets Evaluated). */
const SYSTEM_ONLY: ReadonlySet<JobStatus> = new Set<JobStatus>(['Evaluated']);

const USER_TRANSITIONS: Readonly<Record<JobStatus, readonly JobStatus[]>> = {
  Inbox: ['Applied', 'Discarded', 'SKIP'],
  Evaluated: ['Applied', 'Discarded', 'SKIP'],
  Applied: ['Responded', 'Interview', 'Offer', 'Rejected', 'Discarded'],
  Responded: ['Interview', 'Offer', 'Rejected', 'Discarded'],
  Interview: ['Offer', 'Rejected', 'Discarded'],
  Offer: ['Hired', 'Rejected', 'Discarded'],
  Hired: [],
  Rejected: ['Inbox'],
  Discarded: ['Inbox'],
  SKIP: ['Inbox'],
};

const SYSTEM_TRANSITIONS: Readonly<Partial<Record<JobStatus, readonly JobStatus[]>>> = {
  Inbox: ['Evaluated'],
  Evaluated: ['Evaluated'],
};

export function isStatus(value: unknown): value is JobStatus {
  return typeof value === 'string' && (STATUSES as readonly string[]).includes(value);
}

export function allowedTransitions(from: JobStatus, actor: Actor = 'user'): JobStatus[] {
  if (actor === 'system') return [...(SYSTEM_TRANSITIONS[from] ?? [])];
  return USER_TRANSITIONS[from].filter((s) => !SYSTEM_ONLY.has(s));
}

export type TransitionCheck =
  | { ok: true }
  | { ok: false; code: 'invalid_status' | 'same_status' | 'transition_not_allowed'; message: string };

export function checkTransition(from: JobStatus, to: unknown, actor: Actor = 'user'): TransitionCheck {
  if (!isStatus(to)) {
    return { ok: false, code: 'invalid_status', message: `Unknown status "${String(to)}".` };
  }
  if (from === to && !(actor === 'system' && to === 'Evaluated')) {
    return { ok: false, code: 'same_status', message: `This role is already ${to}.` };
  }
  if (!allowedTransitions(from, actor).includes(to)) {
    return {
      ok: false,
      code: 'transition_not_allowed',
      message: `A role can't move from ${from} to ${to}.`,
    };
  }
  return { ok: true };
}

/** Statuses that count as "active" for follow-ups and Today counts. */
export const ACTIVE_STATUSES: readonly JobStatus[] = ['Applied', 'Responded', 'Interview', 'Offer'];
