export type ChatRole = 'system' | 'user' | 'assistant';
export type ChatMessage = { role: ChatRole; content: string };
export type ReasoningEffort = 'minimal' | 'low' | 'medium' | 'high';

export type Usage = {
  inputTokens: number;
  outputTokens: number;
  cachedInputTokens: number;
  reasoningTokens: number;
};

export const ZERO_USAGE: Usage = { inputTokens: 0, outputTokens: 0, cachedInputTokens: 0, reasoningTokens: 0 };

export type CompletionRequest = {
  messages: ChatMessage[];
  maxOutputTokens: number;
  reasoningEffort: ReasoningEffort;
  jsonSchema?: { name: string; schema: object };
  signal?: AbortSignal;
};

export type CompletionResult = {
  text: string;
  usage: Usage;
  finishReason: string | null;
  model: string;
};

export type StreamChunk = { delta?: string; usage?: Usage; finishReason?: string | null };

/** The only surface the app uses to talk to a model. Azure OpenAI in prod, a fake in tests. */
export interface ChatModel {
  readonly modelName: string;
  complete(req: CompletionRequest): Promise<CompletionResult>;
  stream(req: Omit<CompletionRequest, 'jsonSchema'>): AsyncIterable<StreamChunk>;
}

export class ModelError extends Error {
  readonly code: 'rate_limited' | 'timeout' | 'content_filtered' | 'length' | 'unavailable' | 'bad_output';
  readonly retryable: boolean;
  constructor(code: ModelError['code'], message: string, retryable = false) {
    super(message);
    this.code = code;
    this.retryable = retryable;
  }
}
