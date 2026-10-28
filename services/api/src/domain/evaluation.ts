/**
 * Structured job evaluation contract, adapted from career-ops (MIT) modes/_shared.md and
 * modes/oferta.md: holistic 1-5 score, archetype, blocks A-H, legitimacy, machine summary.
 */
import { list, num, obj, oneOf, str, validate, type Schema } from './json-schema.ts';

export const DECISIONS = ['Apply', 'Consider', 'Research first', 'Skip'] as const;
export const CONFIDENCE = ['High', 'Medium', 'Low'] as const;
export const EVIDENCE = ['supported', 'partial', 'unknown'] as const;
export const IMPORTANCE = ['critical', 'high', 'meaningful', 'preferred', 'low_signal'] as const;
export const EVIDENCE_TIER = ['stated', 'structural', 'inferred'] as const;
export const MATCH = ['Strong', 'Partial', 'Missing', 'N/A'] as const;
export const LEGITIMACY = ['High Confidence', 'Proceed with Caution', 'Suspicious'] as const;
export const WORK_AUTH = ['sponsors', 'not_needed', 'unstated', 'no_sponsorship'] as const;
export const CULTURE = ['pass', 'caution', 'fail', 'unknown'] as const;
export const COMP_RELIABILITY = ['High', 'Medium', 'Low', 'Unknown'] as const;

export const H_BLOCK_MIN_SCORE = 4.5;
export const MAX_REQUIREMENT_ROWS = 12;

export const evaluationSchema: Schema = obj({
  archetype: str('Detected archetype from the candidate targets, or "None of these".'),
  score: num('Holistic global score from 1.0 to 5.0, one decimal. Never an average of blocks.'),
  decision: oneOf(DECISIONS),
  confidence: oneOf(CONFIDENCE),
  verdict: str('One or two sentence lead verdict in plain language.'),
  score_evidence: obj({
    cv_match: oneOf(EVIDENCE),
    north_star: oneOf(EVIDENCE),
    compensation: oneOf(EVIDENCE),
    culture: oneOf(EVIDENCE),
    red_flags: oneOf(EVIDENCE),
  }),
  blocks: obj({
    a_role_summary: obj({
      tldr: str(),
      domain: str(),
      function: oneOf(['build', 'consult', 'manage', 'deploy', 'other']),
      seniority: str(),
      work_model: str('Remote, hybrid, on-site or unknown, as stated.'),
      culture_screen: oneOf(CULTURE),
      culture_evidence: str(),
      work_auth: oneOf(WORK_AUTH),
      work_auth_quote: str('Verbatim JD wording about sponsorship or eligibility, or empty string.'),
    }),
    b_cv_match: obj({
      requirements: list(
        obj({
          requirement: str(),
          importance: oneOf(IMPORTANCE),
          evidence_tier: oneOf(EVIDENCE_TIER),
          jd_signal: str('Verbatim JD quote for stated requirements, else how it was inferred.'),
          match: oneOf(MATCH),
          evidence_or_gap: str('Exact CV evidence, or the gap.'),
          mitigation: str('For critical/high Partial or Missing rows: interview risk and mitigation. Else empty.'),
        }),
      ),
      gaps_strategy: str(),
    }),
    c_level_strategy: obj({
      jd_level: str(),
      candidate_level: str(),
      sell_senior_without_lying: list(str()),
      if_downleveled: str(),
    }),
    d_comp_demand: obj({
      hiring_entity: str(),
      reliability: oneOf(COMP_RELIABILITY),
      advertised_comp: str('Verbatim from the JD, or empty string. Never inferred.'),
      notes: str(),
      hr_questions: list(str()),
    }),
    e_customization: list(
      obj({ section: str(), current_status: str(), proposed_change: str(), why: str() }),
    ),
    f_interview_plan: obj({
      stories: list(obj({ requirement: str(), story: str(), reflection: str() })),
      red_flag_questions: list(obj({ question: str(), honest_answer: str() })),
    }),
    g_legitimacy: obj({
      tier: oneOf(LEGITIMACY),
      positive_signals: list(str()),
      concerns: list(str()),
      notes: str(),
    }),
    h_application_answers: list(obj({ question: str(), draft: str() }), 'Only when score >= 4.5, else empty.'),
  }),
  top_strengths: list(str()),
  hard_stops: list(str()),
  soft_gaps: list(str()),
  keywords: list(str('Exact JD phrases worth mirroring in the CV.')),
  confidence_gaps: list(str('Up to three concrete checks that could change the decision.')),
  next_action: str(),
});

export type Evaluation = {
  archetype: string;
  score: number;
  decision: (typeof DECISIONS)[number];
  confidence: (typeof CONFIDENCE)[number];
  verdict: string;
  score_evidence: Record<'cv_match' | 'north_star' | 'compensation' | 'culture' | 'red_flags', (typeof EVIDENCE)[number]>;
  blocks: {
    a_role_summary: {
      tldr: string;
      domain: string;
      function: string;
      seniority: string;
      work_model: string;
      culture_screen: (typeof CULTURE)[number];
      culture_evidence: string;
      work_auth: (typeof WORK_AUTH)[number];
      work_auth_quote: string;
    };
    b_cv_match: {
      requirements: Array<{
        requirement: string;
        importance: (typeof IMPORTANCE)[number];
        evidence_tier: (typeof EVIDENCE_TIER)[number];
        jd_signal: string;
        match: (typeof MATCH)[number];
        evidence_or_gap: string;
        mitigation: string;
      }>;
      gaps_strategy: string;
    };
    c_level_strategy: { jd_level: string; candidate_level: string; sell_senior_without_lying: string[]; if_downleveled: string };
    d_comp_demand: {
      hiring_entity: string;
      reliability: (typeof COMP_RELIABILITY)[number];
      advertised_comp: string;
      notes: string;
      hr_questions: string[];
    };
    e_customization: Array<{ section: string; current_status: string; proposed_change: string; why: string }>;
    f_interview_plan: {
      stories: Array<{ requirement: string; story: string; reflection: string }>;
      red_flag_questions: Array<{ question: string; honest_answer: string }>;
    };
    g_legitimacy: { tier: (typeof LEGITIMACY)[number]; positive_signals: string[]; concerns: string[]; notes: string };
    h_application_answers: Array<{ question: string; draft: string }>;
  };
  top_strengths: string[];
  hard_stops: string[];
  soft_gaps: string[];
  keywords: string[];
  confidence_gaps: string[];
  next_action: string;
};

export type EvaluationCheck = { ok: true; value: Evaluation } | { ok: false; errors: string[] };

/**
 * Validate model output and apply the deterministic rules the prompt asks for, so a model
 * mistake can't break them: score range and rounding, H only at >= 4.5, row cap.
 */
export function checkEvaluation(raw: unknown): EvaluationCheck {
  const result = validate(evaluationSchema, raw);
  if (!result.ok) return { ok: false, errors: result.errors.slice(0, 20) };
  const value = structuredClone(raw) as Evaluation;
  if (value.score < 1 || value.score > 5) {
    return { ok: false, errors: [`$.score: ${value.score} is outside 1-5`] };
  }
  value.score = Math.round(value.score * 10) / 10;
  if (value.score < H_BLOCK_MIN_SCORE) value.blocks.h_application_answers = [];
  const rows = value.blocks.b_cv_match.requirements;
  if (rows.length > MAX_REQUIREMENT_ROWS) {
    const keep = rows.filter((r) => r.importance === 'critical' || r.importance === 'high');
    const rest = rows.filter((r) => r.importance !== 'critical' && r.importance !== 'high');
    value.blocks.b_cv_match.requirements = [...keep, ...rest].slice(0, Math.max(MAX_REQUIREMENT_ROWS, keep.length));
  }
  // "inferred" evidence can never be critical/high (career-ops rule).
  for (const r of value.blocks.b_cv_match.requirements) {
    if (r.evidence_tier === 'inferred' && (r.importance === 'critical' || r.importance === 'high')) {
      r.importance = 'meaningful';
    }
  }
  value.confidence_gaps = value.confidence_gaps.slice(0, 3);
  return { ok: true, value };
}
