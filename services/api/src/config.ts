/** Environment configuration. Fails fast at startup; never logs secret values. */
export type AppEnv = 'development' | 'test' | 'production';

export type Config = {
  env: AppEnv;
  port: number;
  logLevel: string;
  databaseUrl: string;
  databaseSsl: boolean;
  auth: {
    discoveryUrl: string;
    audience: string;
    requiredScope: string;
  };
  ai: {
    provider: 'azure' | 'dev';
    endpoint: string;
    deployment: string;
    apiVersion: string;
    managedIdentityClientId?: string;
    timeoutMs: number;
  };
  credits: Record<string, number>;
  rateLimits: { aiPerMinute: number; writesPerMinute: number };
  graph?: { tenantId: string; clientId: string; clientSecret: string };
  appInsightsConnectionString?: string;
};

type Env = Record<string, string | undefined>;

function req(env: Env, key: string, errors: string[]): string {
  const v = env[key]?.trim();
  if (!v) errors.push(`${key} is required`);
  return v ?? '';
}

function int(env: Env, key: string, fallback: number, errors: string[]): number {
  const raw = env[key];
  if (raw === undefined || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 0) errors.push(`${key} must be a non-negative integer`);
  return n;
}

export function loadConfig(env: Env = process.env): Config {
  const errors: string[] = [];
  const nodeEnv = (env.NODE_ENV ?? 'development') as AppEnv;
  if (!['development', 'test', 'production'].includes(nodeEnv)) errors.push('NODE_ENV must be development, test or production');

  const provider = (env.AI_PROVIDER ?? 'azure') as 'azure' | 'dev';
  if (provider !== 'azure' && provider !== 'dev') errors.push('AI_PROVIDER must be azure or dev');
  if (provider === 'dev' && nodeEnv === 'production') errors.push('AI_PROVIDER=dev is not allowed in production');

  const ai = {
    provider,
    endpoint: provider === 'azure' ? req(env, 'AZURE_OPENAI_ENDPOINT', errors) : env.AZURE_OPENAI_ENDPOINT ?? '',
    deployment: env.AZURE_OPENAI_DEPLOYMENT?.trim() || 'gpt-5-mini',
    apiVersion: env.AZURE_OPENAI_API_VERSION?.trim() || '2025-04-01-preview',
    managedIdentityClientId: env.AZURE_CLIENT_ID?.trim() || undefined,
    timeoutMs: int(env, 'AI_TIMEOUT_MS', 120_000, errors),
  };

  const graph =
    env.GRAPH_TENANT_ID && env.GRAPH_CLIENT_ID && env.GRAPH_CLIENT_SECRET
      ? { tenantId: env.GRAPH_TENANT_ID, clientId: env.GRAPH_CLIENT_ID, clientSecret: env.GRAPH_CLIENT_SECRET }
      : undefined;

  const config: Config = {
    env: nodeEnv,
    port: int(env, 'PORT', 8080, errors),
    logLevel: env.LOG_LEVEL ?? (nodeEnv === 'production' ? 'info' : 'debug'),
    databaseUrl: req(env, 'DATABASE_URL', errors),
    databaseSsl: (env.DATABASE_SSL ?? (nodeEnv === 'production' ? 'true' : 'false')) === 'true',
    auth: {
      discoveryUrl: req(env, 'AUTH_DISCOVERY_URL', errors),
      audience: req(env, 'AUTH_AUDIENCE', errors),
      requiredScope: env.AUTH_REQUIRED_SCOPE?.trim() || 'access_as_user',
    },
    ai,
    credits: {
      free: int(env, 'AI_MONTHLY_CREDITS_FREE', 150, errors),
      pro: int(env, 'AI_MONTHLY_CREDITS_PRO', 1500, errors),
    },
    rateLimits: {
      aiPerMinute: int(env, 'RATE_LIMIT_AI_PER_MINUTE', 10, errors),
      writesPerMinute: int(env, 'RATE_LIMIT_WRITES_PER_MINUTE', 120, errors),
    },
    graph,
    appInsightsConnectionString: env.APPLICATIONINSIGHTS_CONNECTION_STRING || undefined,
  };

  if (errors.length) throw new Error(`Invalid configuration:\n- ${errors.join('\n- ')}`);
  return config;
}
