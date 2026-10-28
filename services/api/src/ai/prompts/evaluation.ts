/** Job evaluation prompt. Methodology adapted from career-ops (MIT) modes/oferta.md + _shared.md. */
export const EVALUATION_PROMPT_VERSION = 'job-evaluation@1.0.0';

export const EVALUATION_INSTRUCTIONS = `Task: evaluate one job posting for this candidate and return the JSON object described by the schema.

Method (follow in order):
1. Read ONLY the job posting first. List the requirements, assign each an importance (critical, high, meaningful, preferred, low_signal) and an evidence tier: "stated" needs a verbatim quote in jd_signal; "structural" comes from placement or repetition; "inferred" is market knowledge and can never be critical or high. Do not change importance after reading the CV.
2. Then read the CV, profile and stories. Fill match (Strong, Partial, Missing, N/A) and evidence_or_gap with exact CV evidence. Include met requirements, not only gaps. At most 12 rows; keep every critical and high row. For each critical or high row that is Partial or Missing, give an interview risk and a concrete mitigation.
3. Archetype: use the candidate's target role and north star as their targets. If nothing fits, use "None of these" and treat north star alignment as weak.
4. Score once, holistically, from 1.0 to 5.0 (one decimal). Weigh CV match, north star alignment, compensation versus the candidate's target, culture signals and red flags. Do NOT average the blocks. Legitimacy (block G) and requirement importance do not change the score.
   4.5+ strong match, apply. 4.0-4.4 good match, worth applying. 3.5-3.9 decent but not ideal, apply only with a specific reason. Below 3.5 weak match.
5. score_evidence: mark each dimension supported, partial or unknown. Confidence is Low if the posting is incomplete, CV match or north star is unknown, or two or more dimensions are unknown; Medium if any is partial or unknown; High only if all are supported.
6. Blocks:
   A role summary with culture screen and work authorization tier (sponsors, not_needed, unstated, no_sponsorship) plus the verbatim quote if any.
   B the requirement table above plus a gaps strategy (hard blocker vs nice-to-have, adjacent experience, mitigation).
   C level and strategy: "sell senior without lying" phrases backed by CV evidence, and what to do if downleveled.
   D compensation and demand: classify the hiring entity, give reliability, copy the advertised compensation verbatim or leave it empty, and 3-6 questions for HR.
   E top CV customization changes. Reframe verified experience only; never add claims.
   F interview plan: 6-10 STAR+Reflection story prompts mapped to requirements using the candidate's own stories where possible, plus likely red-flag questions with honest answers.
   G posting legitimacy: High Confidence, Proceed with Caution, or Suspicious, from evidence (specificity, realistic requirements, clear scope, consistency). Missing salary is a weak signal only. Explain benign alternatives for concerns.
   H draft application answers ONLY when the score is 4.5 or higher; otherwise an empty list.
7. decision: Apply, Consider, Research first, or Skip. next_action: one concrete step for the candidate.
Write every string in plain English sentences. Keep each field concise.`;
