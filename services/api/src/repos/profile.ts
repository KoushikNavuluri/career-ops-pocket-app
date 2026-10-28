import type { Tx } from '../db/pool.ts';

export type ProfileRow = {
  user_id: string;
  alias: string | null;
  target_role: string | null;
  north_star: string | null;
  target_market: string | null;
  work_model: string | null;
  target_base: number | null;
  currency: string | null;
  include_keywords: string[];
  exclude_keywords: string[];
  work_auth_check: string;
  onboarded_at: Date | null;
  version: number;
  updated_at: Date;
};

export type PreferencesRow = {
  user_id: string;
  theme: string;
  resume_template: string;
  export_format: string;
  posting_verification: boolean;
  weekly_scan: boolean;
  notifications: Record<string, unknown>;
  updated_at: Date;
};

export type ProfilePatch = Partial<{
  alias: string | null;
  target_role: string | null;
  north_star: string | null;
  target_market: string | null;
  work_model: string | null;
  target_base: number | null;
  currency: string | null;
  include_keywords: string[];
  exclude_keywords: string[];
  work_auth_check: string;
  onboarded: boolean;
}>;

const PROFILE_COLUMNS = [
  'alias',
  'target_role',
  'north_star',
  'target_market',
  'work_model',
  'target_base',
  'currency',
  'include_keywords',
  'exclude_keywords',
  'work_auth_check',
] as const;

export async function getProfile(tx: Tx, userId: string): Promise<ProfileRow | null> {
  const r = await tx.query<ProfileRow>('SELECT * FROM profiles WHERE user_id = $1', [userId]);
  return r.rows[0] ?? null;
}

export async function updateProfile(tx: Tx, userId: string, patch: ProfilePatch): Promise<ProfileRow> {
  const sets: string[] = [];
  const values: unknown[] = [userId];
  for (const col of PROFILE_COLUMNS) {
    if (patch[col] !== undefined) {
      values.push(patch[col]);
      sets.push(`${col} = $${values.length}`);
    }
  }
  if (patch.onboarded === true) sets.push('onboarded_at = coalesce(onboarded_at, now())');
  if (patch.onboarded === false) sets.push('onboarded_at = NULL');
  sets.push('version = version + 1');
  const r = await tx.query<ProfileRow>(`UPDATE profiles SET ${sets.join(', ')} WHERE user_id = $1 RETURNING *`, values);
  return r.rows[0]!;
}

export async function getPreferences(tx: Tx, userId: string): Promise<PreferencesRow | null> {
  const r = await tx.query<PreferencesRow>('SELECT * FROM preferences WHERE user_id = $1', [userId]);
  return r.rows[0] ?? null;
}

export type PreferencesPatch = Partial<Pick<PreferencesRow, 'theme' | 'resume_template' | 'export_format' | 'posting_verification' | 'weekly_scan'>>;

export async function updatePreferences(tx: Tx, userId: string, patch: PreferencesPatch): Promise<PreferencesRow> {
  const cols = ['theme', 'resume_template', 'export_format', 'posting_verification', 'weekly_scan'] as const;
  const sets: string[] = [];
  const values: unknown[] = [userId];
  for (const c of cols) {
    if (patch[c] !== undefined) {
      values.push(patch[c]);
      sets.push(`${c} = $${values.length}`);
    }
  }
  if (sets.length === 0) return (await getPreferences(tx, userId))!;
  const r = await tx.query<PreferencesRow>(`UPDATE preferences SET ${sets.join(', ')} WHERE user_id = $1 RETURNING *`, values);
  return r.rows[0]!;
}
