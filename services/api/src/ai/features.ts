import type { ReasoningEffort } from './types.ts';
import { WRITING_FEATURES, WRITING_PROMPT_VERSION, type WritingFeature } from './prompts/writing.ts';
import { EVALUATION_PROMPT_VERSION } from './prompts/evaluation.ts';
import { ASSISTANT_PROMPT_VERSION } from './prompts/assistant.ts';

export type AiFeature = 'job-evaluation' | 'assistant' | WritingFeature;

export type FeatureSpec = {
  id: AiFeature;
  label: string;
  promptVersion: string;
  /** Credits charged against the monthly plan budget. */
  credits: number;
  reasoningEffort: ReasoningEffort;
  /** Includes reasoning tokens for GPT-5 family models. */
  maxOutputTokens: number;
};

const writing = Object.fromEntries(
  WRITING_FEATURES.map((id) => [
    id,
    { id, label: id, promptVersion: WRITING_PROMPT_VERSION, credits: 2, reasoningEffort: 'low', maxOutputTokens: 4000 },
  ]),
) as Record<WritingFeature, FeatureSpec>;

export const FEATURES: Record<AiFeature, FeatureSpec> = {
  'job-evaluation': {
    id: 'job-evaluation',
    label: 'Job evaluation',
    promptVersion: EVALUATION_PROMPT_VERSION,
    credits: 3,
    reasoningEffort: 'low',
    maxOutputTokens: 12000,
  },
  assistant: {
    id: 'assistant',
    label: 'Career assistant',
    promptVersion: ASSISTANT_PROMPT_VERSION,
    credits: 1,
    reasoningEffort: 'minimal',
    maxOutputTokens: 2500,
  },
  ...writing,
};

export function isAiFeature(value: string): value is AiFeature {
  return value in FEATURES;
}

/** Bump when what we send to the model, or to whom, changes. Users re-consent. */
export const CONSENT_POLICY_VERSION = 'ai-consent-2026-10';

export function usagePeriod(now = new Date()): string {
  return now.toISOString().slice(0, 7);
}
