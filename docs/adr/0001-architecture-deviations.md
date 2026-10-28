# ADR 0001: Deviations from the Oct 2026 assessment

Status: accepted (28 Oct 2026)

1. **Fastify 5 instead of NestJS.** One modular API with plain functions is enough at this size;
   Fastify keeps cold starts and dependency count low on Container Apps. Module boundaries stay the same.
2. **Plain SQL migrations instead of Drizzle.** Row-level security, pgvector and partial indexes are
   clearer in SQL. Migrations are forward-only, run at container start behind an advisory lock.
3. **Password auth for PostgreSQL (in Key Vault) for now.** Entra auth for the database is a
   hardening item before production, together with VNet integration and private endpoints.
4. **Assistant context is assembled per request** (profile, pipeline summary, CV excerpt, selected
   role). Embedding-based retrieval over `content_chunks` comes in a later phase.
5. **Working name "Career Ops".** The upstream TRADEMARK.md reserves "career-ops" for commercial
   product names; revisit before store submission.
