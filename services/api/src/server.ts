/** Production entrypoint. */
if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING) {
  const { useAzureMonitor } = await import('@azure/monitor-opentelemetry');
  useAzureMonitor();
}

const { loadConfig } = await import('./config.ts');
const { createDb } = await import('./db/pool.ts');
const { createVerifierFromDiscovery } = await import('./http/auth.ts');
const { createGateway } = await import('./ai/gateway.ts');
const { createAzureChatModel } = await import('./ai/azure-openai.ts');
const { createDevModel } = await import('./ai/dev-model.ts');
const { createGatewayStore } = await import('./repos/ai-store.ts');
const { createGraphClient } = await import('./integrations/graph.ts');
const { buildApp } = await import('./app.ts');

const config = loadConfig();
const db = createDb({ connectionString: config.databaseUrl, ssl: config.databaseSsl });

// Container Apps reaches Postgres privately; running forward-only migrations at boot (behind an
// advisory lock) avoids opening the database to CI runners.
if (process.env.RUN_MIGRATIONS === 'true') {
  const { runMigrations } = await import('./db/migrate.ts');
  const applied = await runMigrations(db.pool, (m) => console.log(`[migrate] ${m}`));
  console.log(`[migrate] ${applied.length ? `applied ${applied.length} migration(s)` : 'database is up to date'}`);
}
const verifyToken = await createVerifierFromDiscovery(config.auth.discoveryUrl, config.auth.audience, config.auth.requiredScope);
const model =
  config.ai.provider === 'azure'
    ? createAzureChatModel({
        endpoint: config.ai.endpoint,
        deployment: config.ai.deployment,
        apiVersion: config.ai.apiVersion,
        managedIdentityClientId: config.ai.managedIdentityClientId,
        timeoutMs: config.ai.timeoutMs,
      })
    : createDevModel();
const gateway = createGateway({
  model,
  store: createGatewayStore(db),
  creditsForPlan: (plan) => config.credits[plan] ?? config.credits.free ?? 0,
});

const app = await buildApp({
  config,
  db,
  verifyToken,
  gateway,
  graph: config.graph ? createGraphClient(config.graph) : undefined,
});

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  await app.close();
  await db.close();
  process.exit(0);
};
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT'));

await app.listen({ host: '0.0.0.0', port: config.port });
app.log.info({ model: model.modelName, env: config.env }, 'career api listening');
