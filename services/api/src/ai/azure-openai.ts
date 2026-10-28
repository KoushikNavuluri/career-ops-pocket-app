/** GPT-5 mini on Azure OpenAI (Microsoft Foundry), authenticated with Entra ID (managed identity). */
import { AzureOpenAI, type OpenAI } from 'openai';
import { DefaultAzureCredential, getBearerTokenProvider } from '@azure/identity';
import {
  ModelError,
  ZERO_USAGE,
  type ChatMessage,
  type ChatModel,
  type CompletionRequest,
  type CompletionResult,
  type StreamChunk,
  type Usage,
} from './types.ts';

export type AzureModelConfig = {
  endpoint: string;
  deployment: string;
  apiVersion: string;
  managedIdentityClientId?: string;
  timeoutMs: number;
};

type MessageParam = OpenAI.Chat.ChatCompletionMessageParam;

type UsageLike =
  | {
      prompt_tokens?: number;
      completion_tokens?: number;
      prompt_tokens_details?: { cached_tokens?: number } | null;
      completion_tokens_details?: { reasoning_tokens?: number } | null;
    }
  | null
  | undefined;

function toParams(messages: ChatMessage[]): MessageParam[] {
  return messages.map((m): MessageParam => {
    if (m.role === 'system') return { role: 'system', content: m.content };
    if (m.role === 'assistant') return { role: 'assistant', content: m.content };
    return { role: 'user', content: m.content };
  });
}

function toUsage(u: UsageLike): Usage {
  if (!u) return ZERO_USAGE;
  return {
    inputTokens: u.prompt_tokens ?? 0,
    outputTokens: u.completion_tokens ?? 0,
    cachedInputTokens: u.prompt_tokens_details?.cached_tokens ?? 0,
    reasoningTokens: u.completion_tokens_details?.reasoning_tokens ?? 0,
  };
}

function mapError(err: unknown): ModelError {
  if (err instanceof ModelError) return err;
  const e = err as { status?: number; code?: string; name?: string; message?: string } | null;
  if (e?.name === 'APIConnectionTimeoutError' || e?.name === 'AbortError') return new ModelError('timeout', 'Timed out', true);
  if (e?.status === 429) return new ModelError('rate_limited', 'Rate limited', true);
  if (e?.status === 400 && (e.code === 'content_filter' || /content.?filter|ResponsibleAIPolicyViolation/i.test(e.message ?? ''))) {
    return new ModelError('content_filtered', 'Filtered');
  }
  return new ModelError('unavailable', e?.message ?? 'Model call failed', true);
}

export function createAzureChatModel(cfg: AzureModelConfig): ChatModel {
  const credential = new DefaultAzureCredential(
    cfg.managedIdentityClientId ? { managedIdentityClientId: cfg.managedIdentityClientId } : undefined,
  );
  const azureADTokenProvider = getBearerTokenProvider(credential, 'https://cognitiveservices.azure.com/.default');
  const client = new AzureOpenAI({
    endpoint: cfg.endpoint,
    deployment: cfg.deployment,
    apiVersion: cfg.apiVersion,
    azureADTokenProvider,
    timeout: cfg.timeoutMs,
    maxRetries: 2,
  });

  async function complete(req: CompletionRequest): Promise<CompletionResult> {
    try {
      const res = await client.chat.completions.create(
        {
          model: cfg.deployment,
          messages: toParams(req.messages),
          max_completion_tokens: req.maxOutputTokens,
          reasoning_effort: req.reasoningEffort,
          ...(req.jsonSchema
            ? {
                response_format: {
                  type: 'json_schema' as const,
                  json_schema: {
                    name: req.jsonSchema.name,
                    strict: true,
                    schema: req.jsonSchema.schema as Record<string, unknown>,
                  },
                },
              }
            : {}),
        },
        { signal: req.signal },
      );
      const choice = res.choices[0];
      if (choice?.finish_reason === 'content_filter') throw new ModelError('content_filtered', 'Filtered');
      return {
        text: choice?.message?.content ?? '',
        usage: toUsage(res.usage),
        finishReason: choice?.finish_reason ?? null,
        model: res.model ?? cfg.deployment,
      };
    } catch (err) {
      throw mapError(err);
    }
  }

  async function* stream(req: Omit<CompletionRequest, 'jsonSchema'>): AsyncIterable<StreamChunk> {
    const open = async () => {
      try {
        return await client.chat.completions.create(
          {
            model: cfg.deployment,
            messages: toParams(req.messages),
            max_completion_tokens: req.maxOutputTokens,
            reasoning_effort: req.reasoningEffort,
            stream: true,
            stream_options: { include_usage: true },
          },
          { signal: req.signal },
        );
      } catch (err) {
        throw mapError(err);
      }
    };
    const source = await open();
    try {
      for await (const chunk of source) {
        const choice = chunk.choices?.[0];
        const out: StreamChunk = {};
        if (choice?.delta?.content) out.delta = choice.delta.content;
        if (choice?.finish_reason) out.finishReason = choice.finish_reason;
        if (chunk.usage) out.usage = toUsage(chunk.usage);
        if (out.delta || out.finishReason || out.usage) yield out;
      }
    } catch (err) {
      throw mapError(err);
    }
  }

  return { modelName: cfg.deployment, complete, stream };
}
