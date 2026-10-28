/**
 * Every AI call goes through here: consent -> quota -> model -> validation -> metering.
 * Content is never logged; only metadata is recorded in ai_runs.
 */
import { AppError } from '../http/errors.ts';
import { parseJsonLoose } from '../domain/json-schema.ts';
import { CONSENT_POLICY_VERSION, FEATURES, usagePeriod, type AiFeature } from './features.ts';
import { ModelError, ZERO_USAGE, type ChatMessage, type ChatModel, type Usage } from './types.ts';

export type AiRunRecord = {
  userId: string;
  feature: AiFeature;
  model: string;
  promptVersion: string;
  usage: Usage;
  credits: number;
  latencyMs: number;
  status: 'ok' | 'error';
  errorCode: string | null;
};

export interface GatewayStore {
  hasConsent(userId: string, feature: AiFeature, policyVersion: string): Promise<boolean>;
  recordConsent(userId: string, feature: AiFeature, policyVersion: string): Promise<void>;
  /** Atomically add credits if the result stays within limit. Returns false when over quota. */
  reserveCredits(userId: string, period: string, credits: number, limit: number): Promise<boolean>;
  refundCredits(userId: string, period: string, credits: number): Promise<void>;
  recordRun(run: AiRunRecord): Promise<string>;
}

export type GatewayOptions = {
  model: ChatModel;
  store: GatewayStore;
  creditsForPlan: (plan: string) => number;
  now?: () => Date;
};

export type CallContext = { userId: string; plan: string; consent?: boolean };

export type StructuredResult<T> = { value: T; runId: string; model: string };
export type TextResult = { text: string; runId: string; model: string };

export function mapModelError(err: unknown): AppError {
  if (err instanceof AppError) return err;
  if (err instanceof ModelError) {
    switch (err.code) {
      case 'rate_limited':
        return new AppError(503, 'ai_busy', 'The AI service is busy. Try again in a moment.', { extra: { retryable: true } });
      case 'timeout':
        return new AppError(504, 'ai_timeout', 'The AI took too long to respond. Try again.', { extra: { retryable: true } });
      case 'content_filtered':
        return new AppError(422, 'ai_content_filtered', 'The request or response was blocked by the safety filter. Rephrase and try again.');
      case 'length':
        return new AppError(502, 'ai_incomplete', 'The AI response was cut off. Try again with a shorter input.', { extra: { retryable: true } });
      case 'bad_output':
        return new AppError(502, 'ai_bad_output', 'The AI returned an answer we could not use. Nothing was saved. Try again.', { extra: { retryable: true } });
      default:
        return new AppError(503, 'ai_unavailable', 'The AI service is unavailable right now. Try again later.', { extra: { retryable: true } });
    }
  }
  return new AppError(503, 'ai_unavailable', 'The AI service is unavailable right now. Try again later.', { extra: { retryable: true } });
}

export function createGateway(opts: GatewayOptions) {
  const now = opts.now ?? (() => new Date());
  const { model, store } = opts;

  async function authorize(ctx: CallContext, feature: AiFeature): Promise<{ period: string; credits: number }> {
    const consented = await store.hasConsent(ctx.userId, feature, CONSENT_POLICY_VERSION);
    if (!consented) {
      if (ctx.consent === true) {
        await store.recordConsent(ctx.userId, feature, CONSENT_POLICY_VERSION);
      } else {
        throw new AppError(403, 'consent_required', 'Confirm that you want to share this context with the AI service.', {
          extra: { feature, policyVersion: CONSENT_POLICY_VERSION },
        });
      }
    }
    const spec = FEATURES[feature];
    const period = usagePeriod(now());
    const ok = await store.reserveCredits(ctx.userId, period, spec.credits, opts.creditsForPlan(ctx.plan));
    if (!ok) {
      throw new AppError(429, 'quota_exceeded', 'You have used this month\'s AI allowance. It resets on the 1st.', {
        extra: { period },
      });
    }
    return { period, credits: spec.credits };
  }

  async function finish(
    ctx: CallContext,
    feature: AiFeature,
    started: number,
    usage: Usage,
    credits: number,
    period: string,
    error: AppError | null,
  ): Promise<string> {
    if (error) await store.refundCredits(ctx.userId, period, credits).catch(() => undefined);
    return store.recordRun({
      userId: ctx.userId,
      feature,
      model: model.modelName,
      promptVersion: FEATURES[feature].promptVersion,
      usage,
      credits: error ? 0 : credits,
      latencyMs: Date.now() - started,
      status: error ? 'error' : 'ok',
      errorCode: error?.code ?? null,
    });
  }

  function addUsage(a: Usage, b: Usage): Usage {
    return {
      inputTokens: a.inputTokens + b.inputTokens,
      outputTokens: a.outputTokens + b.outputTokens,
      cachedInputTokens: a.cachedInputTokens + b.cachedInputTokens,
      reasoningTokens: a.reasoningTokens + b.reasoningTokens,
    };
  }

  return {
    /** JSON-schema output, validated by `check`, with one repair attempt. */
    async structured<T>(
      ctx: CallContext,
      feature: AiFeature,
      messages: ChatMessage[],
      schema: { name: string; schema: object },
      check: (raw: unknown) => { ok: true; value: T } | { ok: false; errors: string[] },
    ): Promise<StructuredResult<T>> {
      const { period, credits } = await authorize(ctx, feature);
      const spec = FEATURES[feature];
      const started = Date.now();
      let usage = ZERO_USAGE;
      try {
        let convo = messages;
        for (let attempt = 0; attempt < 2; attempt++) {
          const res = await model.complete({
            messages: convo,
            jsonSchema: schema,
            maxOutputTokens: spec.maxOutputTokens,
            reasoningEffort: spec.reasoningEffort,
          });
          usage = addUsage(usage, res.usage);
          if (res.finishReason === 'length') throw new ModelError('length', 'Output truncated');
          const parsed = parseJsonLoose(res.text);
          const checked = parsed === undefined ? { ok: false as const, errors: ['Output was not valid JSON'] } : check(parsed);
          if (checked.ok) {
            const runId = await finish(ctx, feature, started, usage, credits, period, null);
            return { value: checked.value, runId, model: res.model };
          }
          convo = [
            ...messages,
            { role: 'assistant', content: res.text.slice(0, 20_000) },
            {
              role: 'user',
              content: `Your previous output failed validation:\n${checked.errors.slice(0, 10).join('\n')}\nReturn the corrected JSON object only.`,
            },
          ];
        }
        throw new ModelError('bad_output', 'Output failed validation twice');
      } catch (err) {
        const appErr = mapModelError(err);
        await finish(ctx, feature, started, usage, credits, period, appErr);
        throw appErr;
      }
    },

    /** Plain text (Markdown) output. */
    async text(ctx: CallContext, feature: AiFeature, messages: ChatMessage[]): Promise<TextResult> {
      const { period, credits } = await authorize(ctx, feature);
      const spec = FEATURES[feature];
      const started = Date.now();
      let usage = ZERO_USAGE;
      try {
        const res = await model.complete({
          messages,
          maxOutputTokens: spec.maxOutputTokens,
          reasoningEffort: spec.reasoningEffort,
        });
        usage = res.usage;
        if (res.finishReason === 'length' && !res.text.trim()) throw new ModelError('length', 'Output truncated');
        if (!res.text.trim()) throw new ModelError('bad_output', 'Empty output');
        const runId = await finish(ctx, feature, started, usage, credits, period, null);
        return { text: res.text.trim(), runId, model: res.model };
      } catch (err) {
        const appErr = mapModelError(err);
        await finish(ctx, feature, started, usage, credits, period, appErr);
        throw appErr;
      }
    },

    /**
     * Streaming text. Authorization happens before the first byte so errors can still be
     * returned as normal HTTP problems. Deltas are pushed to `onDelta`.
     */
    async prepareStream(ctx: CallContext, feature: AiFeature) {
      const { period, credits } = await authorize(ctx, feature);
      const spec = FEATURES[feature];
      return async (messages: ChatMessage[], onDelta: (text: string) => void, signal?: AbortSignal): Promise<TextResult> => {
        const started = Date.now();
        let usage = ZERO_USAGE;
        let text = '';
        try {
          for await (const chunk of model.stream({
            messages,
            maxOutputTokens: spec.maxOutputTokens,
            reasoningEffort: spec.reasoningEffort,
            signal,
          })) {
            if (chunk.delta) {
              text += chunk.delta;
              onDelta(chunk.delta);
            }
            if (chunk.usage) usage = chunk.usage;
            if (chunk.finishReason === 'content_filter') throw new ModelError('content_filtered', 'Filtered');
          }
          if (!text.trim()) throw new ModelError('bad_output', 'Empty output');
          const runId = await finish(ctx, feature, started, usage, credits, period, null);
          return { text: text.trim(), runId, model: model.modelName };
        } catch (err) {
          const appErr = mapModelError(err);
          await finish(ctx, feature, started, usage, credits, period, appErr);
          throw appErr;
        }
      };
    },
  };
}

export type Gateway = ReturnType<typeof createGateway>;
