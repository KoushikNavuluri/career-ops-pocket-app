/**
 * Deterministic model for automated tests and offline UI work. The config refuses to use it
 * when NODE_ENV=production, so it can never answer real users.
 */
import type { ChatModel, CompletionRequest, CompletionResult, StreamChunk } from './types.ts';

export function sampleEvaluation(score = 4.2) {
  return {
    archetype: 'None of these',
    score,
    decision: score >= 4 ? 'Apply' : 'Consider',
    confidence: 'Medium',
    verdict: 'Deterministic test evaluation. Not produced by a language model.',
    score_evidence: { cv_match: 'partial', north_star: 'partial', compensation: 'unknown', culture: 'unknown', red_flags: 'supported' },
    blocks: {
      a_role_summary: {
        tldr: 'Test role summary.',
        domain: 'Software',
        function: 'build',
        seniority: 'Senior',
        work_model: 'unknown',
        culture_screen: 'unknown',
        culture_evidence: '',
        work_auth: 'unstated',
        work_auth_quote: '',
      },
      b_cv_match: {
        requirements: [
          {
            requirement: 'Example requirement',
            importance: 'high',
            evidence_tier: 'stated',
            jd_signal: 'quoted text',
            match: 'Partial',
            evidence_or_gap: 'Gap',
            mitigation: 'Prepare an example.',
          },
        ],
        gaps_strategy: 'Address the gap with adjacent experience.',
      },
      c_level_strategy: { jd_level: 'Senior', candidate_level: 'Senior', sell_senior_without_lying: [], if_downleveled: '' },
      d_comp_demand: { hiring_entity: 'unknown', reliability: 'Unknown', advertised_comp: '', notes: '', hr_questions: [] },
      e_customization: [],
      f_interview_plan: { stories: [], red_flag_questions: [] },
      g_legitimacy: { tier: 'Proceed with Caution', positive_signals: [], concerns: [], notes: '' },
      h_application_answers: [],
    },
    top_strengths: [],
    hard_stops: [],
    soft_gaps: [],
    keywords: [],
    confidence_gaps: [],
    next_action: 'Review the fit.',
  };
}

export function createDevModel(): ChatModel {
  return {
    modelName: 'dev-deterministic',
    async complete(req: CompletionRequest): Promise<CompletionResult> {
      const text = req.jsonSchema ? JSON.stringify(sampleEvaluation()) : 'Deterministic test response.';
      return { text, usage: { inputTokens: 10, outputTokens: 10, cachedInputTokens: 0, reasoningTokens: 0 }, finishReason: 'stop', model: 'dev-deterministic' };
    },
    async *stream(): AsyncIterable<StreamChunk> {
      for (const part of ['Deterministic ', 'test ', 'response.']) yield { delta: part };
      yield { finishReason: 'stop', usage: { inputTokens: 10, outputTokens: 3, cachedInputTokens: 0, reasoningTokens: 0 } };
    },
  };
}
